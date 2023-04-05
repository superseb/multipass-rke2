#!/usr/bin/env bash
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Setup microk8s for use within this code base.
#
# Requires: multipass
#           jq
#
# Author(s): Sebastiaan van Steenis
#            Justin Cook

set -o errexit nounset

## Configurable settings
# Name for the cluster/configuration files
NAME="generic"
# Ubuntu image to use (xenial/bionic/focal/jammy)
IMAGE="jammy"
# RKE2 channel
RKE2_CHANNEL="stable"
# RKE2 version
#RKE2_VERSION="v1.24.12+rke2r1"
# How many master nodes to create
MASTER_NODE_COUNT="1"
# How many compute nodes to create
AGENT_NODE_COUNT="2"
# How many CPUs to allocate to each machine
MASTER_NODE_CPU="2"
AGENT_NODE_CPU="2"
# How much disk space to allocate to each master and compute node
MASTER_DISK_SIZE="20G"
AGENT_DISK_SIZE="40G"
# How much memory to allocate to each machine
MASTER_MEMORY_SIZE="4G"
AGENT_MEMORY_SIZE="8G"
# Preconfigured secret to join the cluster (or autogenerated if empty)
# Note: in order to use this script multiple times to add nodes, this needs
# to be configured.
TOKEN=""
# Hostnames or IPv4/IPv6 addresses as Subject Alternative Names on the server
# TLS cert
TLSSAN="rancher.test"
## End configurable settings
# Where to store the rke2 cluster kubeconfig
LOCALKUBECONFIG="${HOME}/.kube/config-${NAME}"

if [ -x "$(command -v multipass.exe)" ]
then
    # Windows
    MULTIPASSCMD="multipass.exe"
elif [ -x "$(command -v multipass)" ] && [ -x "$(command -v kubectl)" ] && \
     [ -x "$(command -v jq)" ]
then
    # Linux/MacOS
    MULTIPASSCMD="multipass"
    KUBECTL="$(command -v kubectl)"
else
    for dep in "multipass" "kubectl" "jq"
    do
        if ! command -v ${dep}
        then
            echo "${dep}: not in PATH"
            exit 1
        fi
    done
fi

if [ -z "${TOKEN}" ]
then
    TOKEN=$(cat - < /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 20 |\
            head -n 1)
    echo "No agent token given, generated agent token: ${TOKEN}"
fi

# Check if name is given or create random string
if [ -z $NAME ]
then
    NAME=$(cat - < /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 6 |\
           head -n 1)
    echo "No name given, generated name: ${NAME}"
fi

if [ -n "${RKE2_VERSION:-}" ]
then
    CLOUD_INIT_INSTALL="INSTALL_RKE2_VERSION=${RKE2_VERSION}"
else
    CLOUD_INIT_INSTALL="INSTALL_RKE2_CHANNEL=${RKE2_CHANNEL}"
fi

cleanup() {
    for file in ${SUBDIR:-./}${NAME}-{pm,master,agent}-cloud-init.yaml
    do
        rm -f "${file}" >/dev/null 2>&1
    done
}
trap cleanup EXIT

# Prepare cloud-init template
# Requires: INSTALL_RKE2_TYPE set which defaults to empty string
#           CONFIGYAML set which is a string of YAML
#           RKE2ROLE set which defaults to "server"
create_cloudinit_template() {
    CLOUDINIT_TEMPLATE=$(cat - << EOM
#cloud-config

runcmd:
 - '\curl -sfL https://get.rke2.io | ${CLOUD_INIT_INSTALL} ${IRT:-} sh -'
 - '\mkdir -p /etc/rancher/rke2'
 - '\echo "${CONFIGYAML}" > /etc/rancher/rke2/config.yaml'
 - '\systemctl daemon-reload'
 - '\systemctl enable --now rke2-${RKE2ROLE:-server}'
EOM
)
}

# A convenience function called throughout the code to create multipass
# instances. It requires arguments passed:
# 1: instance name
# 2: number of cpus
# 3: disk size
# 4: memory size
# 5: image name
# 6: cloud-init file name
create_multipass_node() {
    echo "Creating ${1} node"
    ${MULTIPASSCMD} launch --cpus "${2}" --disk "${3}" --memory "${4}" "${5}" \
    --name "${1}" --cloud-init "${SUBDIR:-./}${6}" --timeout=600
}

# A convenience function called throughout the code to detect node registration
# and wait until ready. The node name needs passed.
wait_on_node() {
    echo "Confirming ${1} registration"
    ${MULTIPASSCMD} exec "${NAME}-rke2-master-1" -- bash -c "$(cat - <<__EOF__
until /var/lib/rancher/rke2/bin/kubectl \
--kubeconfig /etc/rancher/rke2/rke2.yaml get "node/${1}"
do
    sleep 2
done
__EOF__
)"
    echo "Waiting for ${1} to become ready"
    ${MULTIPASSCMD} exec "${NAME}-rke2-master-1" -- /bin/bash -c "$(cat - <<__EOF__
/var/lib/rancher/rke2/bin/kubectl \
--kubeconfig /etc/rancher/rke2/rke2.yaml wait --for=condition=Ready \
"node/${1}" --timeout=600s
__EOF__
)"
}

cat << __EOF__
Creating cluster ${NAME} with ${MASTER_NODE_COUNT} masters and \
${AGENT_NODE_COUNT} nodes.
__EOF__

# Server specific cloud-init
CONFIGYAML="token: ${TOKEN}\nwrite-kubeconfig-mode: 644\ntls-san: ${TLSSAN}"
create_cloudinit_template
echo "${CLOUDINIT_TEMPLATE}" > "${NAME}-pm-cloud-init.yaml"

if ! ${MULTIPASSCMD} info "${NAME}-rke2-master-1" >/dev/null 2>&1
then
    create_multipass_node "${NAME}-rke2-master-1" ${MASTER_NODE_CPU} \
        ${MASTER_DISK_SIZE} ${MASTER_MEMORY_SIZE} ${IMAGE} \
        "${NAME}-pm-cloud-init.yaml"
fi
wait_on_node "${NAME}-rke2-master-1"

# Retrieve info to join agent to cluster
SERVER_IP=$($MULTIPASSCMD info "${NAME}-rke2-master-1" --format=json | \
            jq -r ".info.\"${NAME}-rke2-master-1\".ipv4[0]")
URL="https://${SERVER_IP}:9345"

# Create additional masters
if [ "${MASTER_NODE_COUNT}" -gt 1 ]
then
    CONFIGYAML="server: ${URL}\ntoken: ${TOKEN}\nwrite-kubeconfig-mode: 644\ntls-san: ${TLSSAN}"
    create_cloudinit_template
    echo "${CLOUDINIT_TEMPLATE}" > "${NAME}-master-cloud-init.yaml"
    for ((i=2; i<=MASTER_NODE_COUNT; i++))
    do
        if ! ${MULTIPASSCMD} info "${NAME}-rke2-master-${i}" >/dev/null 2>&1
        then
            create_multipass_node "${NAME}-rke2-master-${i}" ${MASTER_NODE_CPU} \
                ${MASTER_DISK_SIZE} ${MASTER_MEMORY_SIZE} ${IMAGE} \
                "${NAME}-master-cloud-init.yaml"
        fi
        wait_on_node "${NAME}-rke2-master-${i}"
    done
fi

# Prepare agent node cloud-init
CONFIGYAML="server: ${URL}\ntoken: ${TOKEN}"
IRT='INSTALL_RKE2_TYPE="agent"'
RKE2ROLE="agent"
create_cloudinit_template
echo "${CLOUDINIT_TEMPLATE}" > "${NAME}-agent-cloud-init.yaml"
for ((i=1; i<=AGENT_NODE_COUNT; i++))
do
    if ! ${MULTIPASSCMD} info "${NAME}-rke2-agent-${i}" >/dev/null 2>&1
    then
        create_multipass_node "${NAME}-rke2-agent-${i}" ${AGENT_NODE_CPU} \
            ${AGENT_DISK_SIZE} ${AGENT_MEMORY_SIZE} ${IMAGE} \
            "${NAME}-agent-cloud-init.yaml"
    fi
    wait_on_node "${NAME}-rke2-agent-${i}"
done

# Retrieve the kubeconfig, edit server address, and merge it with the local
# kubeconfig in order to use contexts.
# shellcheck disable=SC2086
if [ ! -d "$(dirname ${LOCALKUBECONFIG})" ]
then
    # shellcheck disable=SC2086
    mkdir "$(dirname ${LOCALKUBECONFIG})"
fi
${MULTIPASSCMD} copy-files "${NAME}-rke2-master-1:/etc/rancher/rke2/rke2.yaml" - | \
sed "/^[[:space:]]*server:/ s_:.*_: \"https://${SERVER_IP}:6443\"_" > \
    "${LOCALKUBECONFIG}"
chmod 0600 "${LOCALKUBECONFIG}"

"${KUBECTL}" config delete-context "${NAME}-rke2-cluster" || /usr/bin/true
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}:${LOCALKUBECONFIG}"
# shellcheck disable=SC2086
if [ ! -d "$(dirname ${KUBECONFIG%%:*})" ]
then
    # shellcheck disable=SC2086
    mkdir "$(dirname ${KUBECONFIG%%:*})"
fi
"${KUBECTL}" config view --flatten > "${KUBECONFIG%%:*}"
"${KUBECTL}" config set-context "${NAME}-rke2-cluster" --namespace default

echo "rke2 setup complete"
"${KUBECTL}" get nodes

echo "Please configure ${TLSSAN} to resolve to ${SERVER_IP}"
