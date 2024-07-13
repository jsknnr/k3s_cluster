# k3s_cluster
Automation for deploying a single node k3s cluster (environemnt is a better word). This was built for quickly deploying or redeploying my local lab and decided others might find it useful. When I eventually add more hardware to my lab I will expand this to handle multi-node installations as well

### What it does
Deploys single node k3 instance with Flannel CNI disabled, no network policy, no kube proxy, no traefik ingress, and no Klipper LB.

Instead we install Cilium CNI with API Gateway support and BGP Control Plane enabled. Your environment will need to support BGP.

cert-manager is also installed utilizing Lets Encrypt production and staging environments with AWS Route53 integration with DNS01 challenges. So you will need a Route53 account, or modify the scripts to use something different.

ArgoCD is installed and configured with TLS certificates from cert-manager with Gateway API TLS termination as I simply couldn't get the passthrough functionality to work right. ArgoCD is configured to disable admin auth and instead configured to use GitHub oauth. So you will need to setup a GitHub oauth in your GitHub account or configure a different provider.

### How to use
Scripts for deploying and destroying the cluster are in `./scripts`. Execute scripts from the root of the project, as that is where everything expects to run from. The manifests and values files for deploying the above services are found under the `./manifests` directory. They are jinja templates.

- Rename `./config/environment.yaml.example` to `./config/environment.yaml`
- Configure the variables in the `environment.yaml` file
- Review global variables at top of `deploy_cluster.sh` script to modify to match your environment, specifically:
    - `K8S_SERVICE_HOST`
    - `K8S_SERVICE_PORT`
    - `K3S_NODE_NAME`
- Export the environment variables for `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` that are used for creating the secret for cert-manager r53 integration
    - documentation for policy and roles here https://cert-manager.io/docs/configuration/acme/dns01/route53/
- Execute `./scripts/deploy_cluster.sh`

This is expected to run on the k3s node locally. In the future I will add support for remote execution. The k3s node should have bash shell, python >= 3.10, curl, and helm 3.

This repo's `.gitignore` is set to ignore all yaml files to prevent accidental commit of potentially sensative information that may be in the yaml files

### Destroying Cluster
To destroy the cluster run `./scripts/destroy_cluster.sh yes-i-really-mean-it`
