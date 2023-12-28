#!/bin/bash -eu

${MULTIPASSCMD}  mount $PWD generic-rke2-master-1:/hostFileDir || true
${MULTIPASSCMD} exec generic-rke2-master-1 -- sudo /hostFileDir/installKubeVIP $RKE2_VIP_IP $RKE2_VIP_INTERFACE

echo verifying that a service referencing $RKE2_VIP_IP is handled by the ingress...

echo waiting for $RKE2_VIP_IP  respond
while ! ping -c 4 $RKE2_VIP_IP > /dev/null 2>&1
do
	echo "The network connection to $RKE2_VIP_IP is not up yet"
	sleep 1
done
kubectl get deployment demo > /dev/null 2>&1 || {
	kubectl create deployment demo --image=httpd --port=80
	kubectl expose deployment demo
	kubectl create ingress demo --class=nginx --rule www.demo.io/=demo:80
}

echo waiting for up to 30 seconds for the $RKE2_VIP_IP  / curl to work...
for x in `seq 1 30`
do
	curl -fs $RKE2_VIP_IP  -H 'Host: www.demo.io' && {
		echo "VIP at $RKE2_VIP_IP is working as an ingress :)"
	        if ping -c 1 rancher.test > /dev/null 2>&1
		then
		        echo "Changing KUBECONFIG to reference ${TLSSAN} instead of ${SERVER_IP}"
		        perl -pi -e "s|${SERVER_IP}|rancher.test|" `echo ${KUBECONFIG} | tr ':' ' '`  ${LOCALKUBECONFIG}
		else
			echo rancher.test is not resolve-able, leaving the LOCALKUBECONFIG configured with master-1 address
		fi
		exit 0
	}
	sleep 1
done
echo accessing VIP at $RKE2_VIP_IP  failed
exit 1
