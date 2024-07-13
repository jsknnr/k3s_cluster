#!/usr/bin/env bash
# Cleanup and Destroy LOCAL k3s cluster
# Currently only works for single node k3s install
# If I ever get around to adding more hardware to my environment I will make this handle multiple nodes

# Make sure someone doesn't fail at tab completion
if [ -z $1 ] || ! [ {$1,,} = "yes-i-really-mean-it" ]; then
    echo "This script destroys k3s cluster"
    echo "must call script with 'yes-i-really-mean-it' argument"
    echo "example: ./scripts/destroy_cluster.sh yes-i-really-mean-it"
    exit 1
fi

echo "Destroying cluster..."

k3s-killall.sh
systemctl stop k3s
k3s-uninstall.sh

exit 0
