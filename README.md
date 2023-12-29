# rke2 cluster on multipass instances

This script will create a configurable amount of instances using [multipass](https://github.com/CanonicalLtd/multipass/), install [rke2](https://github.com/rancher/rke2) server, and add additional server/agent instances to the cluster.

## Requirements

* multipass (See [multipass: Getting it](https://github.com/CanonicalLtd/multipass#getting-it))

This is tested on MacOS and Ubuntu Linux 22.04.

## Running it

Clone this repo, and run the script:

```
bash multipass-rke2.sh
```

This will (defaults):

* Use `generic` as name for your cluster (configurable using `NAME`)
* Create one master (configurable using `MASTER_NODE_COUNT`) with 2 CPU (`MASTER_NODE_CPU`), 20G disk (`MASTER_DISK_SIZE`) and 4G of memory (`MASTER_MEMORY_SIZE`) using Ubuntu jammy (`IMAGE`)
* Create two agents (configurable using `AGENT_NODE_COUNT`) with 2 CPU (`AGENT_NODE_CPU`), 40G disk (`AGENT_DISK_SIZE`) and 8G of memory (`AGENT_MEMORY_SIZE`) using Ubuntu jammy (`IMAGE`)
* Additional certificate names (`tls-san`) is set to `rancher.test` (configurable using `TLSSAN`)
* Store kubeconfig in `${HOME}/.kube/config-${NAME}` (configurable using `LOCALKUBECONFIG`)
* Install ([kube-vip ](https://kube-vip.io/)) with support for both ingress and High Availability if rancher.test is configured with the VIP address
* Allows for access of the cluster using the VIP address instead of the first of N masters and continues to operate when a master node is offline

## Quickstart Ubuntu 22.04 droplet

```
sudo snap install multipass jq
wget https://raw.githubusercontent.com/superseb/multipass-rke2/master/multipass-rke2.sh
bash multipass-rke2.sh
curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl --kubeconfig $HOME/.kube/config-* get nodes
```

## Clean up

You can clean up the instances by running `remove_rke2.sh`, this only works for the default cluster `NAME` (`generic`).
