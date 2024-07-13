#!/usr/bin/env bash
# https://docs.k3s.io/installation/configuration - k3s intall configuration docs
# https://docs.k3s.io/cli/server - k3s server configuration parameters
# https://docs.k3s.io/reference/env-variables - k3s environment variables
# https://docs.cilium.io/en/stable/installation/k3s/ - k3s specific docs
# https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#kubeproxy-free - Install with kube-proxy replacement
# https://docs.cilium.io/en/stable/network/bgp-toc/ - Install BGP Control Plane
# https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/#prerequisites - Install Gateway API
# https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#dex - ArgoCD OAUTH with GitHub

CILIUM_VERSION="1.15.7"
CERT_MANAGER_VERSION="v1.15.1"
# Unless you modify the k3s install command and override this default, you shouldn't have to change this
CLUSTER_POOL_CIDR="10.42.0.0/16"
# IP or FQDN of K3 node
K8S_SERVICE_HOST="172.16.100.20"
# Port for API service on K3 node
K8S_SERVICE_PORT="6443"
# Hostname of K3 node
K3S_NODE_NAME="apollo"

# Function to wait for a pod to be running before proceeding
# `kubectl rollout` doesn't work well without sleeping and waiting before calling so let's just do this
wait_for_pod () {
  # $1 = namespace
  # $2 = pod label name to check
  set +e
  count=0
  while true; do
    sleep 5
    if oc get pod -n $1 -l $2 | awk '{print $3}' | grep -q 'Running'; then
      sleep 5
      break
    fi
    echo "$(timestamp) - INFO - Waiting for $2 pods to be ready"
    sleep 5
    if [ $count -gt 60 ]; then
      echo "$(timestamp) - ERROR - Timeout waiting for $2"
      exit 1
    else
      ((count++))
    fi
  done
  set -e
}

# Setup Python environment for running our manifest generator
. ./scripts/setup.sh

# Install K3s with no Flannel CNI, no network policy, no kube proxy, no traefik ingress, and no Klipper LB
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy --disable-kube-proxy --disable=traefik --disable=servicelb' sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install k8s Gateway API CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.0.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Install Cilium
# clusterPoolIPv4 needs to match K3s cluster cidr - 10.42/16 is default if not specified in k3s install
# k8sService host and port should match k3s node or Cilium will not come up
cilium install --version ${CILIUM_VERSION} \
    --set=ipam.operator.clusterPoolIPv4PodCIDRList="${CLUSTER_POOL_CIDR}" \
    --set=bgpControlPlane.enabled=true \
    --set kubeProxyReplacement=true \
    --set gatewayAPI.enabled=true \
    --set k8sServiceHost=${K8S_SERVICE_HOST} \
    --set k8sServicePort=${K8S_SERVICE_PORT}

wait_for_pod kube-system "app.kubernetes.io/name=cilium-agent"

# Label our node for BGP policy advertisement
kubectl label nodes ${K3S_NODE_NAME} cilium-bgp="enabled"

# Render Cilium manifests
./scripts/render_template.py -d ./manifests/cilium -c ./config/environment.yaml
# Apply CiliumBGPPeeringPolicy and CiliumLoadBalancerIPPool manifests
kubectl apply -f ./manifests/cilium/CiliumBGPControlPlane.yaml

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version ${CERT_MANAGER_VERSION} \
    --set crds.enabled=true \
    --set "extraArgs={--enable-gateway-api}"

wait_for_pod cert-manager "app.kubernetes.io/name=cert-manager"

# Create secret for AWS Route 53 access
kubectl create secret generic route53-credentials -n cert-manager \
    --from-literal=aws_access_key_id=${AWS_ACCESS_KEY_ID} \ 
    --from-literal=aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}

# Render cert-manager manifests
./scripts/render_template.py -d ./manifests/cert-manager -c ./config/environment.yaml
# Deploy Lets Encrypt staging and production cluster issuers
kubectl -n cert-manager apply -f ./manifests/cert-manager/staging_issuer.yaml
kubectl -n cert-manager apply -f ./manifests/cert-manager/production_issuer.yaml

# Render argocd manifests
./scripts/render_template.py -d ./manifests/argocd -c ./config/environment.yaml
# Deploy ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm --force-update
# ArgoCD configured for OAUTH via GitHub
# Must setup OAUTH app for GH organization first
# https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#dex
helm upgrade --install --namespace argocd --create-namespace argocd argo/argo-cd -f ./manifests/argocd/values.yaml

wait_for_pod argocd "app.kubernetes.io/name=argocd-server"

kubectl -n argocd apply -f ./manifests/argocd/gateway.yaml
