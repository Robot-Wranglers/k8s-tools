#!/usr/bin/env -S make -f
####################################################################################
# demos/argo-events.mk: 
#   Automation for a self-contained cluster with anargo-events deployment.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
# This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
#
# See the documentation here[1] for more discussion.
#
# USAGE: 
#
#   # Default runs clean, create, deploy, test, but does not tear down the cluster
#   ./demos/argo-events.mk
#
#   # End-to-end, again without teardown 
#   ./demos/argo-events.mk clean create deploy test
#
#   # Finally, teardown the cluster
#   ./demos/argo-events.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include compose.mk 
include k8s.mk

# Ensure local KUBECONFIG exists & ignore anything from environment
export KUBECONFIG:=./local.cluster.yml
export _:=$(shell umask 066;touch ${KUBECONFIG})

# Cluster details that will be used by k3d.
export CLUSTER_NAME:=k8s-tools-argo-events
export ARGO_WORKFLOWS_VERSION=3.5.4

# Default entrypoint should do everything, end to end.
__main__: clean create deploy test

# Generate target-scaffolding for k8s-tools.yml services
$(eval $(call compose.import, k8s-tools.yml))

# Cluster lifecycle basics.  These are the same for all demos, and mostly just
# setting up aliases for existing targets.  The `*.pre` targets setup hooks 
# for declaring stage-entry.. this is part of formatting friendly output.#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
clean.pre: flux.stage/cluster.clean
clean cluster.clean teardown: k3d.cluster.delete/$${CLUSTER_NAME}
create.pre: flux.stage/cluster.create
create cluster.create: k3d.cluster.get_or_create/$${CLUSTER_NAME}
wait cluster.wait: k8s.cluster.wait

# Deployment & tests for ArgoWF and Argo Events.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# https://argoproj.github.io/argo-events/quick_start/
define argo.events.manifests
 https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/event-sources/webhook.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/master/examples/rbac/sensor-rbac.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/master/examples/rbac/workflow-rbac.yaml
 https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/sensors/webhook.yaml
endef
argo.manifest=https://github.com/argoproj/argo-workflows/releases/download/v${ARGO_WORKFLOWS_VERSION}/install.yaml

deploy: argo.setup argo.events.setup k8s.wait
	@# Note that this is not idempotent and fails on a second usage!
	mapping="12000:12000" ${make} kubefwd.start/argo-events/webhook-eventsource-svc

argo.setup:; $(call containerized.maybe, k8s)
.argo.setup: k8s.kubens.create/argo
	kubectl apply -f ${argo.manifest}

argo.events.setup:; $(call containerized.maybe, k8s)
.argo.events.setup: k8s.kubens.create/argo-events
	${mk.def.read}/argo.events.manifests | ${io.xargs} "kubectl apply -f %"

test:
	curl -d '{"message":"this is my first webhook"}' \
		-H "Content-Type: application/json" \
		-X POST http://webhook-eventsource-svc:12000/example
	${make} k8s.get/argo-events/workflows