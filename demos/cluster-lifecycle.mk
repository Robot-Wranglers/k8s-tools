#!/usr/bin/env -S make -f
# demos/cluster-lifecycle.mk: 
#   Demonstrating full cluster lifecycle automation with k8s-tools.git.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
#   This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
#
#   See the documentation here for more discussion: 
#
#   USAGE: 
#
#     # Default entrypoint runs clean, create, deploy, test, but does not tear down the cluster.  
#     ./demos/cluster-lifecycle.mk
#
#     # End-to-end, again without teardown 
#     ./demos/cluster-lifecycle.mk clean create deploy test
#
#     # Interactive shell for a cluster pod
#     ./demos/cluster-lifecycle.mk cluster.shell 
#
#     # 
#     ./demos/cluster-lifecycle.mk cluster.show
#
#     # Finally, teardown the cluster
#     ./demos/cluster-lifecycle.mk teardown

include compose.mk 
include k8s.mk

# Override k8s-tools.yml service-defaults, 
# explicitly setting the k3d version used
export K3D_VERSION:=v5.6.3

# Cluster details that will be used by k3d.
export CLUSTER_NAME:=k8s-tools-e2e

# Ensure local KUBECONFIG exists & ignore anything from environment
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

# Chart & Pod details that we'll use later during deploy
export HELM_REPO:=https://helm.github.io/examples
export HELM_CHART:=examples/hello-world
export POD_NAME?=test-harness
export POD_NAMESPACE?=default

# Generate target-scaffolding for k8s-tools.yml services
$(eval $(call compose.import, k8s-tools.yml, ▰))

__main__: flux.and/clean,create,deploy,test

###############################################################################

clean cluster.clean: flux.stage/cluster.clean k3d.dispatch/k3d.cluster.delete/$${CLUSTER_NAME}
create cluster.create: \
	flux.stage/cluster.create \
	k3d.dispatch/self.cluster.maybe.create
teardown: flux.stage/cluster.teardown cluster.teardown

wait cluster.wait: k8s.cluster.wait
self.cluster.maybe.create: flux.do.unless/self.cluster.create,self.cluster.exists
self.cluster.exists: k3d.has_cluster/$${CLUSTER_NAME}
self.cluster.create: k3d.cluster.get_or_create/$${CLUSTER_NAME}

###############################################################################

deploy cluster.deploy: \
	flux.stage/cluster.deploy \
	flux.loop.until/k8s.cluster.ready \
	deploy.helm deploy.test_harness deploy.prometheus
	# add a label to the default namespace
	key=manager val=k8s.mk ${make} k8s.namespace.label/${POD_NAMESPACE}

deploy.prometheus:
	${json.from} name=prometheus-community \
		chart_ref=prometheus chart_version=25.24.1 \
		release_namespace=prometheus create_namespace=yes wait=yes \
		chart_repo_url="https://prometheus-community.github.io/helm-charts" \
	| ${make} ansible.helm

fwd.grafana:
	mapping="80:8081" ${make} kubefwd.start/prometheus/grafana
	$(call log.k8s, looking up grafana password) 
	grafana_password=`kubectl get secret --namespace prometheus grafana -o jsonpath="{.data.admin-password}"\
	| base64 --decode` \
	&& printf "http://admin:$${grafana_password}@grafana:8081\n"
	
deploy.grafana:
	${json.from} \
		name=grafana chart_ref=grafana \
		wait=yes values:raw='{"adminPassword":"test"}' \
		create_namespace=yes release_namespace=prometheus \
		chart_repo_url=https://grafana.github.io/helm-charts \
	| ${make} ansible.helm
	
deploy.helm:
	${json.from} name=ahoy chart_ref=hello-world \
		release_namespace=default chart_repo_url="https://helm.github.io/examples" \
	| ${make} ansible.helm io.time.wait/5

deploy.test_harness: flux.retry/3/k8s.dispatch/self.test_harness.deploy
self.test_harness.deploy: \
	k8s.kubens.create/${POD_NAMESPACE} \
	k8s.test_harness/${POD_NAMESPACE}/${POD_NAME} \
	k8s.kubectl.apply/demos/data/nginx.svc.yml

cluster.teardown:
	${json.from} wait=yes kind=Pod state=absent name=${POD_NAME} namespace=${POD_NAMESPACE} \
	| ${make} k8s.ansible
	${json.from} wait=true name=ahoy state=absent release_namespace=default \
	| ${make} ansible.helm 

###############################################################################

test: test.cluster test.contexts 
test.cluster cluster.test: flux.stage/cluster.test cluster.wait
	label="Showing kubernetes status" \
		${make} io.print.banner k8s.stat 
	label="Previewing topology for default namespace" \
		${make} io.print.banner k8s.graph.tui/default/pod
	label="Previewing topology for kube-system namespace" \
		${make} io.print.banner k8s.graph.tui/kube-system/pod
	label="Previewing topology for prometheus namespace" \
		${make} io.print.banner k8s.graph.tui/prometheus/pod

test.contexts: 
	@# Helpers for displaying platform info 
	label="Demo pod connectivity" ${make} io.print.banner 
	${make} get.compose.ctx get.pod.ctx 

get.compose.ctx:
	@# Runs on the container defined by compose service
	echo uname -n | ${make} k8s-tools/k8s/shell/pipe

get.pod.ctx:
	@# Runs inside the kubernetes cluster
	echo uname -n | ${make} k8s.shell/${POD_NAMESPACE}/${POD_NAME}/pipe

###############################################################################

cluster.shell: k8s.shell/${POD_NAMESPACE}/${POD_NAME}
