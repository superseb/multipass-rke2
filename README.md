# rke2 cluster on multipass instances

This script will create a configurable amount of instances using [multipass](https://github.com/CanonicalLtd/multipass/), install [rke2](https://github.com/rancher/rke2) server, and add additional server/agent instances to the cluster.

## Requirements

* multipass (See [multipass: Getting it](https://github.com/CanonicalLtd/multipass#getting-it))

This is tested on MacOS, Ubuntu Linux 20.04 and Windows 10.

## Running it

Clone this repo, and run the script:

```
bash multipass-rke2.sh
```

This will (defaults):


* Generate random name for your cluster (configurable using `NAME`)
* Create init-cloud-init file for server to install the first rke2 server
* Create one instance for the first server with 2 CPU (`SERVER_CPU_MACHINE`), 10G disk (`SERVER_DISK_MACHINE`) and 4G of memory (`SERVER_MEMORY_MACHINE`) using Ubuntu focal (`IMAGE`)
* Create cloud-init file for server to install additional rke2 servers
* Create one instance for additional server (configurable using `SERVER_COUNT_MACHINE`)
* Create cloud-init file for agent to join the cluster
* Create one machine (configurable using `AGENT_COUNT_MACHINE`) with 1 CPU (`AGENT_CPU_MACHINE`), 10G disk (`AGENT_DISK_MACHINE`) and 2G of memory (`AGENT_MEMORY_MACHINE`) using Ubuntu focal (`IMAGE`)
* Wait for the nodes to be joined to the cluster

## Quickstart Ubuntu 20.04 droplet

```
sudo snap install multipass --classic
wget https://raw.githubusercontent.com/superseb/multipass-rke2/master/multipass-rke2.sh
bash multipass-rke2.sh
curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl
kubectl --kubeconfig *-kubeconfig.yaml get nodes
```

## Clean up

The files that are created are:

* `$NAME-init-cloud-init.yaml`
* `$NAME-cloud-init.yaml`
* `$NAME-agent-cloud-init.yaml`
* `$NAME-kubeconfig.yaml`
* `$NAME-kubeconfig-orig.yaml`

You can clean up the instances by running `multipass delete rke2-server-$NAME --purge`, `multipass delete rke2-server-$NAME-{1,2,3} --purge` and `multipass delete rke2-agent-$NAME-{1,2,3}` or (**WARNING** this deletes and purges all instances): `multipass delete --all --purge`
