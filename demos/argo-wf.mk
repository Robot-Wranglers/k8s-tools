#!/usr/bin/env -S make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# demos/argo-wf.mk: 
#   Automation for a self-contained argo-workflows cluster with k8s-tools.git.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
# This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
#
# See the documentation here[1] for more discussion.
#
# USAGE: 
#
#   # Default: clean/create/deploy/test for cluster without any teardown
#   ./demos/argo-wf.mk
#
#   # End-to-end, again without teardown 
#   ./demos/argo-wf.mk clean create deploy test
#
#   # Finally, teardown the cluster
#   ./demos/argo-wf.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk

# Cluster details that will be used by k3d.
export CLUSTER_NAME:=k8s-tools-argowf

# Ensure local KUBECONFIG exists & ignore anything from environment
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

# Default entrypoint should do everything, end to end.
__main__: clean create deploy test

# Generate target-scaffolding for k8s-tools.yml services
$(eval $(call compose.import, k8s-tools.yml))

# Cluster lifecycle basics.  These are the same for all demos, and mostly just
# setting up aliases for existing targets.  The `*.pre` targets setup hooks 
clean.pre: flux.stage/cluster.clean
clean cluster.clean teardown: k3d.cluster.delete/$${CLUSTER_NAME}
create.pre: flux.stage/cluster.create
create cluster.create: k3d.cluster.get_or_create/$${CLUSTER_NAME}
wait cluster.wait: k8s.cluster.wait

# Finished with boilerplate.  Start the argo-specific deploy/test process
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

argo_namespace=argo
argo_workflows_version="v3.6.4"
argo_repo=https://github.com/argoproj/argo-workflows
argo_repo_raw=https://raw.githubusercontent.com/argoproj/argo-workflows
argo_app_url=${argo_repo_raw}/main/examples/hello-world.yaml
argo_infra_url=${argo_repo}/releases/download/${argo_workflows_version}/quick-start-minimal.yaml

deploy.pre: flux.stage/cluster.deploy
deploy cluster.deploy: \
	flux.loop.until/k8s.cluster.ready \
	infra.setup
	
test.pre: flux.stage/test
test: infra.test app.test

infra.setup: argo.dispatch/.infra.setup 
.infra.setup: k8s.wait k8s.kubens.create/${argo_namespace}
	url="${argo_infra_url}" ${make} kubectl.apply.url

infra.test: argo.dispatch/.infra.test
	label="Previewing topology for argo namespace" \
		${make} io.print.banner k8s.graph.tui/${argo_namespace}/pod
.infra.test: k8s.kubens/${argo_namespace} argo.list

app.test: argo.dispatch/.app.test
.app.test: k8s.kubens/${argo_namespace}
	@# Shows three ways to submit jobs
	${mk.def.read}/argo.wf.template | ${argo.submit.stdin}
	$(call io.mktemp) && ${mk.def.to.file}/argo.wf.template/$${tmpf} \
	&& ${make} argo.submit/$${tmpf} 
	url="${argo_app_url}" ${make} argo.submit.url

# BEGIN: Embedded data
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define argo.wf.template
  apiVersion: argoproj.io/v1alpha1
  kind: Workflow
  metadata:
    generateName: hello-world-
    labels:
      workflows.argoproj.io/archive-strategy: "false"
    annotations:
      workflows.argoproj.io/description: |
        This is a simple hello world example.
  spec:
    entrypoint: hello-world
    templates:
    - name: hello-world
      container:
        image: busybox
        command: [echo]
        args: ["hello world"]
endef
