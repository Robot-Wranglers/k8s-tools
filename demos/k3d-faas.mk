####################################################################################
# Project automation.
#
# USAGE: `make clean bootstrap deploy test`
# 	- clean: tears down the k3d cluster and all apps
# 	- bootstrap: bootstraps the k3d cluster and cluster-auth
# 	- deploy: deploys all infrastructure and applications
# 	- test: runs all infrastructure and application tests
#
# NOTE: 
#   This project uses k8s-tools.git automation to dispatch commands 
#   into the containers described inside `k8s-tools.yml`. See the full 
#   docs here[1].  Summarizing calling conventions: targets written like
#   "▰/myservice/.target_name" describe a callback so that container 
#   "myservice" will run "make .target_name".
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools
####################################################################################
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
export CLUSTER_NAME:=k8s-tools-faas

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
all: clean create deploy test

cluster.teardown:
# printf "wait=yes kind=Pod state=absent name=test-harness namespace=default" \
# | ${make} jb | ${make} k8s.ansible
# printf "\
# 	wait=true \
# 	name=ahoy \
# 	state=absent \
# 	release_namespace=default" \
# | ${make} jb \
# | ${make} ansible.helm 


# project.show: ▰/k8s/show
# .show:
# 	@#
# 	echo CLUSTER_NAME=$${CLUSTER_NAME}
# 	echo KUBECONFIG=$${KUBECONFIG}
# 	kubectl cluster-info
# 	kubectl get nodes
# 	kubectl get namespace

# clean: cluster.clean docker.stop.all
# bootstrap: docker.init cluster.bootstrap project.show

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
 self.cluster.create: flux.do.unless/.self.cluster.create,k3d.has_cluster/$${CLUSTER_NAME}
# ( k3d cluster list | grep $${CLUSTER_NAME} \
#   || ${make} .self.cluster.create )
.self.cluster.create:; k3d cluster create $${CLUSTER_NAME} \
			--servers 3 --agents 3 \
			--api-port 6551 --port '8080:80@loadbalancer' \
			--volume $$(pwd)/:/$${CLUSTER_NAME}@all --wait )
	
self.cluster.clean:
	set -x && k3d cluster delete $${CLUSTER_NAME}
	
deploy: deploy.infra deploy.apps
deploy.infra: fission_infra.setup argo_infra.setup #knative_infra.setup 
deploy.apps: fission_app.setup #knative_app.setup

test: #fission_infra.test fission_app.test knative_infra.test knative_app.test

# END: Top-level
####################################################################################
# BEGIN: Cluster-ops:: These targets use the `k3d` container

cluster.bootstrap: ▰/k3d/.cluster.setup ▰/k3d/.cluster.auth
cluster.clean: ▰/k3d/.cluster.clean
.cluster.clean:
	k3d cluster delete $${CLUSTER_NAME}
.cluster.setup:
	(k3d cluster list | grep $${CLUSTER_NAME} ) \
	|| k3d cluster create \
		--config $${KUBECONFIG} \
		--api-port 6551 --servers 1 \
		--agents $${CLUSTER_AGENT_COUNT} \
		--port 8080:80@loadbalancer \
		--volume `pwd`:/$${CLUSTER_NAME}@all \
		--wait
.cluster.auth:
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}

# END: Cluster-ops
####################################################################################
# BEGIN: Fission Infra/Apps :: 
#   Infra uses `kubectl` container, but apps require the `fission` container for CLI
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/

export FISSION_NAMESPACE?=fission
fission_infra.setup: ▰/k8s/.fission_infra.setup #io.time.wait/30 project.show
fission_infra.teardown: ▰/k8s/.fission_infra.teardown
fission_infra.test: ▰/fission/.fission_infra.test
fission_infra.test: ▰/fission/.fission_infra.test
.fission_infra.setup:
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl create namespace $${FISSION_NAMESPACE}
	kubectl config set-context --current --namespace=$${FISSION_NAMESPACE}
	kubectl apply -f https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml
	kubectl config set-context --current --namespace=default
.fission_infra.teardown: 
	namespace=$${FISSION_NAMESPACE} make k8s.namespace.purge 
.fission_infra.test: #fission_infra.auth
	fission version && echo "----------------------"
	fission check && echo "----------------------"

# FIXME: 
# .fission_infra.auth: $(eval $(call FISSION_AUTH_TOKEN))
# define FISSION_AUTH_TOKEN
# FISSION_AUTH_TOKEN=`\
# 		kubectl get secrets -n $${FISSION_NAMESPACE} -o json \
# 		| jq -r '.items[]|select(.metadata.name|startswith("fission-router")).data.token' \
# 		| base64 -d`
# endef


fission_app.setup: fission_infra.test
fission_app.setup: ▰/fission/.fission_app.deploy
fission_app.setup: io.time.wait/35 fission_app.test
fission_app.test: ▰/fission/.fission_app.test
.fission_app.deploy:
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
.fission_app.test:
	@#
	(fission function list | grep fission-app) \
		|| fission function create --name fission-app --env python \
			--code demos/data/src/fission/app.py \
	&& fission function test --timeout=0 --name fission-app

# END: Fission infra/apps
####################################################################################
# BEGIN: Knative Infra / Apps ::
#   Dispatching to `kubectl` container and `kn` container for the the `kn` and `func` CLI
#   - https://knative.run/article/How_to_deploy_a_Knative_function_on_Kubernetes.html
#   - https://knative.dev/docs/getting-started/first-service/
#   - https://knative.dev/docs/samples/
export KNATIVE_NAMESPACE_PREFIX := knative-
knative_infra.setup: ▰/k8s/.knative_infra.setup
knative_infra.test: ▰/kn/.knative_infra.test
knative_infra.teardown: ▰/k8s/.knative_infra.teardown
.knative_infra.setup:
	kubectl create -f https://github.com/knative/operator/releases/download/knative-v1.5.1/operator-post-install.yaml || true
	kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.14.0/operator.yaml || true
	${make} .knative_infra.serving
.knative_infra.serving:
	kubectl apply --validate=false -f https://github.com/knative/serving/releases/download/v0.25.0/serving-crds.yaml
	kubectl apply --validate=false -f https://github.com/knative/serving/releases/download/v0.25.0/serving-core.yaml
.knative_infra.auth:
	echo knative_infra.auth placeholder
.knative_infra.test:
	func version
	kn version
	kubectl get pods --namespace knative-serving
	cd demos/data/src/knf/; tree
.knative_infra.teardown: 
	${make} k8s.namespace.list \
	| grep $${KNATIVE_NAMESPACE_PREFIX} \
	| xargs -n1 -I% bash -x -c "namespace=% make k8s.namespace.purge"

knative_app.test: ▰/kn/.knative_app.test
knative_app.setup: ▰/kn/.knative_app.setup
.knative_app.setup:
	echo app-placeholder
.knative_app.test:
	echo test-placeholder

# END: Knative infra/apps
####################################################################################

# https://argoproj.github.io/argo-events/quick_start/
export ARGO_NAMESPACE_PREFIX:=argo
argo: argo_infra.teardown argo_infra.setup 
argo_infra.setup: ▰/k8s/.argo_infra.setup
argo_infra.teardown: ▰/k8s/.argo_infra.teardown
.argo_infra.teardown: 
	${make} k8s.namespace.list 
.argo_infra.setup:
	helm repo list | grep $${ARGO_NAMESPACE_PREFIX} || helm repo add argo https://argoproj.github.io/argo-helm
	helm install argo-events argo/argo-events -n $${ARGO_NAMESPACE_PREFIX}-events --create-namespace
	kubectl apply -n argo-events \
		-f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml