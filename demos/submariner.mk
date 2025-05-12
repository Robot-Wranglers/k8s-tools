#!/usr/bin/env -S make -f
# demos/submariner.mk: 
#   Demonstrating multicluster networking with minikube, calico, 
#   and submariner.  Verbs include: create, destroy, deploy, etc.
#   
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
# Note that repeatedly setting up calico can quickly run into rate-limiting 
# with docker.io, and you might want to setup a local registry mirror [2]
#
# USAGE: 
#
#   # Default entrypoint runs clean, create, deploy, 
#   # and tests, but does does not tear down the cluster.  
#   ./demos/submariner.mk
#
#   # End-to-end, again without teardown 
#   ./demos/submariner.mk clean create deploy test
#
#   # Interactive shell for a cluster pod
#   ./demos/submariner.mk cluster.shell 
#
#   # Finally, teardown the cluster
#   ./demos/submariner.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/submariner/
#   [2] https://gist.github.com/trisberg/37c97b6cc53def9a3e38be6143786589
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Boilerplate section.
# Ensures local KUBECONFIG exists & ignores anything from environment
# Sets cluster details that will be used by k3d.
# Generates target-scaffolding for k8s-tools.yml services
# Setup the default target that will do everything, end to end.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})

$(call compose.import, file=k8s-tools.yml)
__main__: clean create deploy test

# Details for multi-cluster bootstrap.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

east.pod_cidr=10.244.0.0/16
east.service_cidr=10.240.0.0/16
west.pod_cidr=10.245.0.0/16
west.service_cidr=10.241.0.0/16
minikube.args=--driver=docker \
	--network-plugin=cni --cni=calico \
	-v1 --wait=all --embed-certs

clean: stage/clean flux.map/minikube.delete,east,west
wait: k8s.cluster.wait
test: stage/test wait test.infra test.app
test.infra: flux.map/test.infra,east,west
create: stage/create \
	minikube.dispatch/self.create/east \
	minikube.dispatch/self.create/west \
	docker.network.connect/east,west
self.create/%:
	export minikube_extra="--service-cluster-ip-range=${${*}.service_cidr}" \
	&& minikube_extra+=" --extra-config=kubeadm.pod-network-cidr=${${*}.pod_cidr}" \
	&& ${make} minikube.cluster.get_or_create/${*}

deploy: stage/deploy deploy.infra wait deploy.app

deploy.infra: \
	networking/east \
	networking/west \
	subctl.dispatch/broker.start \
	subctl.dispatch/clusters.join

networking/%:; $(call containerized.maybe, k8s)
.networking/%:
	@# NB: calico is partially installed by minikube already, 
	@# so we must allow partial updates during CRDs installed by 
	@# kubectl create, hence the `strict=0` used below.
	kubectx ${*}
	$(call log.k8s, ${@} ${sep} Starting calico installation..)
	strict=0 ${make} kubectl.create/demos/data/tigera-operator-v3.29.0.yml
	${make} kubectl.namespace.wait/all
	${mk.def.read}/calico.installation.yml \
		| ${yq} . -o json \
		| ${jq} '.spec.calicoNetwork.ipPools[0].cidr="${${*}.service_cidr}"' \
		| ${stream.peek} \
		| ${kubectl.apply.stdin}
	$(call log.k8s, ${@} ${sep} Patch IP pool and label gateway)
	( \
		kubectl patch ippool default-ipv4-ippool \
			--context ${*} --type=merge \
			-p '{"spec": {"ipipMode": "Never", "vxlanMode": "Always"}}' \
		&& kubectl label node --context ${*} ${*} submariner.io/gateway=true \
	) | ${stream.as.log}

broker.start:
	$(call log.k8s, ${@} ${sep} Starting broker on cluster-east)
	subctl deploy-broker --context east

clusters.join: io.wait/30
	subctl show brokers --context east
	$(call log.k8s, ${@} ${sep} Joining east to mesh..)
	subctl join broker-info.subm --natt=false --clusterid east --context east
	${make} io.wait/30
	$(call log.k8s, ${@} ${sep} Joining west to mesh..)
	subctl join broker-info.subm --natt=false --clusterid west --context west
	${make} io.wait/30

test.infra/%:; $(call containerized.maybe, subctl)
.test.infra/%:
	$(call log.k8s, ${@} ${sep} Submariner diagnostics)
	(   set -x \
		&& kubectl get pod -n submariner-operator --context east \
		&& kubectl get pod -n submariner-operator --context west \
		&& subctl show all --context ${*} \
		&& subctl diagnose all --context ${*} ) \
	2> /dev/stdout | ${stream.nl.compress} | ${stream.indent}

deploy.app: flux.map/k8s.dispatch/.app.deploy,east,west k8s.wait 
.app.deploy/%:
	$(call log.k8s,app.deploy ${sep} ${*} ${sep} Deploying test apps)
	kubectl apply -f demos/data/nginx.yml --context ${*} \
	&& kubectl apply -f demos/data/nginx.svc.yml --context ${*}

nginx.get=kubectl get pods -l app=nginx
nginx.name=${nginx.get} -o jsonpath='{.items[0].metadata.name}'
nginx.ip=${nginx.get} -o jsonpath='{.items[0].status.podIP}'
test.app: io.wait/20 k8s.dispatch/.test.app
.test.app:
	western=`${nginx.name} --context west` && west_pod=`${nginx.ip} --context west ` \
	&& eastern=`${nginx.name} --context east` && east_pod=`${nginx.ip} --context east` \
	&& $(call log.k8s, ${@} ${sep} Eastern pod ${sep}${dim} $${eastern} @ $${east_pod}) \
	&& $(call log.k8s, ${@} ${sep} Western pod ${sep}${dim} $${western} @ $${west_pod}) \
	&& $(call log.k8s, ${@} ${sep} Checking west-to-east connectivity..) \
	&& kubectl exec --context west -i $${western} -- \
		curl -sS $${east_pod} | ${stream.nl.compress} | ${stream.as.log} \
	&& $(call log.k8s, ${@} ${sep} Checking east-to-west connectivity..) \
	&& kubectl exec --context east -i $${eastern} -- \
		curl -sS $${west_pod} | ${stream.nl.compress} | ${stream.as.log}

define calico.installation.yml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: __REPLACED__
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
endef