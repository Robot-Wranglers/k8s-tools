#!/usr/bin/env -S make -f
# demos/minikube.mk: 
#   Demonstrating full cluster lifecycle automation with k8s-tools.git.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
# This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
# See the documentation here[1] for more discussion.  Note that this can quickly run 
# into rate-limiting from docker.io, and you might want to setup a local registry 
# mirror.  See [2]
#
# USAGE: 
#
#   # Default entrypoint runs clean, create, deploy, 
#   # and tests, but does does not tear down the cluster.  
#   ./demos/minikube.mk
#
#   # End-to-end, again without teardown 
#   ./demos/minikube.mk clean create deploy test
#
#   # Interactive shell for a cluster pod
#   ./demos/minikube.mk cluster.shell 
#
#   # Finally, teardown the cluster
#   ./demos/minikube.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/minikube/
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
export MINIKUBE_IN_STYLE=0
$(shell umask 066; touch ${KUBECONFIG})
$(shell mkdir -p ./.minikube)
$(eval $(call compose.import, k8s-tools.yml))
__main__: clean create deploy test

# Cluster lifecycle basics.  These are similar for all demos, 
# and mostly just setting up CLI aliases for existing targets. 
# The `flux.stage` are just announcing sections, `k3d.*` are library calls.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

east.pod_cidr=10.244.0.0/16
east.service_cidr=10.240.0.0/16
west.pod_cidr=10.245.0.0/16
west.service_cidr=10.241.0.0/16
minikube.args=--driver=docker --network-plugin=cni --cni=calico -v1 --wait=apiserver --embed-certs
calico.url=https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml

clean teardown cluster.clean: flux.stage/cluster.clean minikube.purge
wait cluster.wait: k8s.cluster.wait
test cluster.test: flux.stage/test.cluster cluster.wait infra.test app.test

create cluster.create: flux.stage/cluster.create k8s.dispatch/.create
.create:
	$(call log.k8s,Configuring clusters..)
	set -x \
	&& minikube start -p east \
		${minikube.args} \
		--service-cluster-ip-range=${east.service_cidr} \
		--extra-config=kubeadm.pod-network-cidr=${east.pod_cidr} \
	&& minikube start -p west \
		${minikube.args} \
		--service-cluster-ip-range=${west.service_cidr} \
		--extra-config=kubeadm.pod-network-cidr=${west.pod_cidr} \
	&& docker network connect east west 

deploy: flux.stage/deploy k8s.dispatch/.deploy/east k8s.dispatch/.deploy/west
.deploy/%:
	$(call log.k8s,Configuring clusters..)
	set -x \
	&& (\
		kubectl create -f ${calico.url} --context ${*} \
		|| true ) \
	&& ${make} kubectl.namespace.wait/all
	kubectx ${*} && ${make} kubectl.namespace.wait/all \
	&& kubectl label node ${*} submariner.io/gateway=true --context ${*} \
	&& kubectl apply -f c.${*}.yml --context ${*} \
	&& kubectl apply -f demos/data/nginx.yml --context ${*} \
	&& kubectl apply -f demos/data/nginx.svc.yml --context ${*} \
	&& kubectl patch ippool default-ipv4-ippool \
		--context ${*} --type=merge \
		-p '{"spec": {"ipipMode": "Never", "vxlanMode": "Always"}}'
.deploy/%: 
	subctl deploy-broker --context east
	${make} io.wait/30 
	subctl show brokers --context east
	subctl join broker-info.subm --natt=false --clusterid east --context east
	subctl join broker-info.subm --natt=false --clusterid west --context west
	${make} io.wait/30 

infra.test: subctl.dispatch/.infra.test 
.infra.test: 
	subctl show all
	subctl diagnose all

app.test: k8s.dispatch/.app.test
.app.test:
	kubectl get pod -n submariner-operator --context east
	kubectl get pod -n submariner-operator --context west