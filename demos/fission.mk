#!/usr/bin/env -S make -f
####################################################################################
# demos/fission.mk: 
#   Demo a self-contained functions-as-a-service with k3d, fission, & k8s-tools.git.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
# This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
#
# See the documentation here[1] for more discussion.
#
# USAGE: 
#
#     # Default runs clean, create, deploy, test, but does not tear down the cluster
#     ./demos/fission.mk
#
#     # End-to-end, again without teardown 
#     ./demos/fission.mk clean create deploy test
#
#     # Finally, teardown the cluster
#     ./demos/fission.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools
####################################################################################

# Boilerplate.  
# Ensures local KUBECONFIG exists & ignore anything from environment
# Sets cluster details that will be used by k3d.
# Generates target-scaffolding for k8s-tools.yml services
# Setup the default target that will do everything, end to end.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
include k8s.mk
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})
export CLUSTER_NAME:=k8s-tools-fission
$(eval $(call compose.import, k8s-tools.yml))
__main__: clean create deploy test

# Cluster lifecycle basics.  These are the same for all demos, and mostly just
# setting up aliases for existing targets.  The `*.pre` targets setup hooks 
# for declaring stage-entry.. optional but it keeps output formatting friendly.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
clean.pre: flux.stage/cluster.clean
clean cluster.clean teardown cluster.teardown: k3d.cluster.delete/$${CLUSTER_NAME}
create.pre: flux.stage/cluster.create
create cluster.create: k3d.cluster.get_or_create/$${CLUSTER_NAME}
wait cluster.wait: k8s.cluster.wait
test: flux.stage/test infra.test k8s.wait app.test
deploy: flux.stage/deploy infra.setup app.setup

# Local cluster details
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

export FISSION_NAMESPACE?=fission

infra.setup: flux.stage/infra.setup k8s.dispatch/.infra.setup k8s.wait
.infra.setup: k8s.kubens.create/$${FISSION_NAMESPACE}
	(kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.21.0" 2>&1 || true) | ${stream.as.log} \
	&& url="https://github.com/fission/fission/releases/download/v1.21.0/fission-all-v1.21.0-minikube.yaml" \
	${make} kubectl.apply.url \
	&& ${make} k8s.kubens/default

infra.teardown: k8s.dispatch/k8s.namespace.purge/$${FISSION_NAMESPACE}

infra.test: flux.stage/infra.test fission.stat

app.setup: flux.stage/app.setup infra.test app.deploy k8s.wait app.test

app.deploy: flux.stage/app.deploy fission.dispatch/.app.deploy
.app.deploy: k8s.kubens/default 
	img=fission/python-env ${make} fission.env.create/python

app.test: flux.stage/app.test k8s.wait fission.dispatch/.app.test
.app.test: k8s.kubens/default fission.stat
	set -x \
	&& fission function create \
			--name fission-app --env python \
			--code demos/data/src/fission/app.py \
	&& ${make} k8s.wait \
	&& fission function test --timeout=0 --name fission-app
