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
#     make -f demos/cluster-lifecycle.mk
#
#     # End-to-end, again without teardown 
#     make -f demos/cluster-lifecycle.mk clean create deploy test
#
#     # Interactive shell for a cluster pod
#     make -f demos/cluster-lifecycle.mk cluster.shell 
#
#     # 
#     make -f demos/cluster-lifecycle.mk cluster.show
#
#     # Finally, teardown the cluster
#     make -f demos/cluster-lifecycle.mk teardown

include k8s.mk

.DEFAULT_GOAL := all 

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
$(eval $(call compose.import, ▰, TRUE, k8s-tools.yml))

# Default target should do everything, end to end.
all: flux.and/clean,create,deploy,test

###############################################################################

# Top level public targets for cluster operations, 
# plus (optional) convenience-aliases and stage-labels.

# These run private subtargets inside the named  tool containers (i.e. `k3d`).
clean cluster.clean: flux.stage/cluster.clean ▰/k3d/self.cluster.clean
create cluster.create: flux.stage/cluster.create ▰/k3d/self.cluster.create
teardown: flux.stage/cluster.teardown cluster.teardown

# Plus a convenience alias to wait for all pods in all namespaces.
wait cluster.wait: k8s.cluster.wait

# Private targets for low-level cluster-ops.
# Host has no `k3d` command, so these targets
# run inside the `k3d` service from k8s-tools.yml
#  ./compose.mk flux.do.unless/<umbrella>,<dry>
self.cluster.create: flux.do.unless/.self.cluster.create/$${CLUSTER_NAME},k3d.has_cluster/$${CLUSTER_NAME}
# ( k3d cluster list | grep $${CLUSTER_NAME} \
#   || ${make} .self.cluster.create )
.self.cluster.create/%:
	k3d cluster create ${*} \
	--servers 3 --agents 3 \
	--api-port 6551 --port '8080:80@loadbalancer' \
	--volume $$(pwd)/:/${*}@all --wait
# k3d.	
self.cluster.clean: k3d.cluster.delete/$${CLUSTER_NAME}

###############################################################################

# Top level public targets for deployments & (optional) convenience-aliases and stage-labels.
# These run private subtargets inside the named  tool containers (i.e. `helm`, and `k8s`).
deploy cluster.deploy: \
	flux.stage/cluster.deploy \
	flux.loop.until/k8s.cluster.ready \
	deploy.helm deploy.test_harness deploy.prometheus
	# add a label to the default namespace
	key=manager val=k8s.mk ${make} k8s.namespace.label/${POD_NAMESPACE}
deploy.prometheus:
	${jb} wait=yes \
		create_namespace=yes \
		chart_ref=prometheus \
		chart_version=25.24.1 \
		name=prometheus-community \
		release_namespace=prometheus \
		chart_repo_url="https://prometheus-community.github.io/helm-charts" \
	| ${make} ansible.helm
fwd.grafana:
	mapping="80:8081" ${make} kubefwd.start/prometheus/grafana
	$(call log, ${GLYPH_DOCKER} looking up grafana password) 
	grafana_password=`kubectl get secret --namespace prometheus grafana -o jsonpath="{.data.admin-password}"|base64 --decode` \
	&& printf "http://admin:$${grafana_password}@grafana:8081\n"
	
deploy.grafana:
	printf "\
		wait=yes \
		name=grafana \
		chart_ref=grafana \
		create_namespace=yes \
		values:raw='{\"adminPassword\":\"test\"}' \
		release_namespace=prometheus \
		chart_repo_url=https://grafana.github.io/helm-charts" \
	| ${make} jb \
	| ${make} ansible.helm
	
deploy.helm: ▰/helm/self.cluster.deploy_helm_example io.time.wait/5
deploy.test_harness: flux.retry/3/▰/k8s/self.test_harness.deploy

# Private targets with the low-level details for what to do in tool containers. 
# You can expand this to include usage of `kustomize`, etc. Volumes are already setup,
# so you can `kubectl apply` from the filesystem.  You can also call anything documented 
# in the API[1] https://github.com/robot-wranglers/k8s-tools/tree/master/docs/api/#k8smk.
self.cluster.deploy_helm_example: 
	@# Idempotent version of a helm install.
	@# Commands are inlined directly below for clarity, 
	@# but see also 'helm.repo.add', 'helm.chart.install', 
	@# and 'ansible.helm' for more advanced built-in helpers.
	set -x \
	&& (helm repo list 2>/dev/null | grep examples || helm repo add examples ${HELM_REPO} ) \
	&& (helm list | grep hello-world || helm install ahoy ${HELM_CHART})

# We stood up the test-harness with the 'k8s.test_harness' target,
# and stood up nginx with plain kubectl.  Let's tear down with 
# ansible to mix it up.
cluster.teardown:
	${jb} wait=yes kind=Pod state=absent name=test-harness namespace=default \
	| ${make} k8s.ansible
	${jb} wait=true name=ahoy state=absent release_namespace=default \
	| ${make} ansible.helm 

# Prerequisites up top create & activate the `default` namespace 
# and then deploy a pod named `test-harness` into it, using a default image.
# In the body, we'll use kubectl directly to deploy a simple service into the default namespace.
self.test_harness.deploy: k8s.kubens.create/${POD_NAMESPACE} k8s.test_harness/${POD_NAMESPACE}/${POD_NAME} 
	ls demos/data/nginx.svc.yml \
	&& kubectl apply -f demos/data/nginx.svc.yml

###############################################################################

test: test.cluster test.contexts 
test.cluster cluster.test: flux.stage/cluster.test cluster.wait
	label="Showing kubernetes status" ${make} io.gum.style 
	${make} k8s/dispatch/k8s.stat 
	label="Previewing topology for default namespace" ${make} io.gum.style 
	size=40x ${make} k8s.graph.tui/default/pod
	label="Previewing topology for kube-system namespace" ${make} io.gum.style 
	${make} k8s.graph.tui/kube-system/pod
	label="Previewing topology for prometheus namespace" ${make} io.gum.style 
	${make} k8s.graph.tui/prometheus/pod

test.contexts: 
	@# Helpers for displaying platform info 
	label="Demo pod connectivity" ${make} io.gum.style 
	${make} get.compose.ctx get.pod.ctx 

get.compose.ctx:
	@# Runs on the container defined by compose service
	echo uname -n | ${make} k8s-tools/k8s/shell/pipe

get.pod.ctx:
	@# Runs inside the kubernetes cluster
	echo uname -n | ${make} k8s.shell/default/test-harness/pipe

###############################################################################

# Interactive shell for the test-harness pod 
# (See the 'deploy' steps for the setup of same)
cluster.shell: k8s.shell/${POD_NAMESPACE}/${POD_NAME}

# TUI for browsing the cluster 
cluster.show: k3d.commander

###############################################################################
