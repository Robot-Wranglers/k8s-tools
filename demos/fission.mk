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
include compose.mk
include k8s.mk

# Ensure local KUBECONFIG exists & ignore anything from environment
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})


# Cluster details that will be used by k3d.
export CLUSTER_NAME:=k8s-tools-fission

export FISSION_NAMESPACE?=fission

# Generate target-scaffolding for k8s-tools.yml services
$(eval $(call compose.import, k8s-tools.yml))

# Default target should do everything, end to end.
__main__: clean create deploy test

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
clean.pre: flux.stage/cluster.clean
clean cluster.clean teardown cluster.teardown: k3d.cluster.delete/$${CLUSTER_NAME}

create.pre: flux.stage/cluster.create
create cluster.create: k3d.cluster.get_or_create/$${CLUSTER_NAME}

wait cluster.wait: k8s.cluster.wait
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


test: flux.stage/test fission.infra.test fission.app.test
deploy: flux.stage/deploy fission.infra.setup fission.app.setup

# END: Top-level
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# BEGIN: Fission Infra/Apps :: 
#   Infra uses `kubectl` container, but apps require the `fission` container for CLI
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/

fission.infra.setup: flux.stage/fission.infra.setup k8s.dispatch/.fission.infra.setup k8s.wait
.fission.infra.setup: k8s.kubens.create/$${FISSION_NAMESPACE}
	(kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" 2>&1 || true) | ${stream.as.log} \
	&& url="https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml" \
	${make} kubectl.apply.url \
	&& ${make} k8s.kubens/default

fission.infra.teardown: k8s.dispatch/kubectl.namespace.purge/$${FISSION_NAMESPACE}

fission.infra.test: flux.stage/fission.infra.test  fission.dispatch/.fission.infra.test
.fission.infra.test: #fission.infra.auth
	set -x && fission version && fission check

fission.app.setup: flux.stage/fission.app.setup fission.infra.test fission.app.deploy k8s.wait fission.app.test

fission.app.deploy: flux.stage/fission.app.deploy fission.dispatch/.fission.app.deploy
.fission.app.deploy: k8s.kubens/default
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env

fission.app.test: flux.stage/fission.app.test  flux.retry/3/fission.dispatch/.fission.app.test
.fission.app.test: k8s.kubens/default
	(fission function list | grep fission-app) \
		|| fission function create \
			--name fission-app --env python \
			--code demos/data/src/fission/app.py \
	&& ${make} k8s.wait \
	&& fission function test --timeout=0 --name fission-app
