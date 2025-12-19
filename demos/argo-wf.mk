#!/usr/bin/env -S make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Demonstrates a self-contained argo-workflows cluster, 
# cluster lifecycle, job submission, etc.
#
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#
#   # Default runs clean, create, deploy, test, but does not tear down the cluster
#   ./demos/argo-wf.mk
#
#   # End-to-end, again without teardown 
#   ./demos/argo-wf.mk clean create deploy test
#
#   # Finally, teardown the cluster
#   ./demos/argo-wf.mk clean
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/argo-wf
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


# Boilerplate section.
# Ensures local KUBECONFIG exists & ignore anything from environment
# Sets cluster details that will be used by k3d.
# Generates target-scaffolding for k8s-tools.yml services
# Setup the default target that will do everything, end to end.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include .cmk/compose.mk 
include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})
$(call compose.import, file=k8s-tools.yml)

__main__: clean create deploy test

# Cluster lifecycle basics.  These are similar for all demos, 
# and mostly just setting up aliases for existing targets. 
# The `stage` usage announces sections, `k3d.*` are library calls.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

cluster.name=argo-wf

clean: stage/cluster.clean k3d.cluster.delete/${cluster.name}
create: stage/cluster.create k3d.cluster.get_or_create/${cluster.name}
test: stage/cluster.test wait infra.test app.test
wait: k8s.wait

# Local cluster details
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

argo.namespace=argo
argo.workflows_version="v3.6.4"
argo.repo=https://github.com/argoproj/argo-workflows
argo.repo_raw=https://raw.githubusercontent.com/argoproj/argo-workflows
argo.app_url=${argo.repo_raw}/main/examples/hello-world.yaml
argo.infra_url=${argo.repo}/releases/download/${argo.workflows_version}/quick-start-minimal.yaml

deploy: stage/cluster.deploy infra.setup

# Dispatches the private-target inside a container, 
# then waits for the cluster to settle.
infra.setup: argo.dispatch/self.infra.setup wait
self.infra.setup: k8s.kubens.create/${argo.namespace}
	kubectl apply -f ${argo.infra_url} | ${stream.as.log}

infra.test: argo.dispatch/self.infra.test
	@# Show details about post-deploy pod/service topology,
	@# Uses context-managers for namespaces, and lists known workflows.
	label="Previewing topology for argo namespace" \
		${make} io.print.banner k8s.graph.tui/${argo.namespace}/pod
self.infra.test: k8s.kubens/${argo.namespace} argo.list

# Shows many different ways to submit jobs
app.test: argo.dispatch/self.app.test
self.app.test: k8s.kubens/${argo.namespace}
	# Use argo CLI directly
	argo submit --log --wait demos/data/argo-job1.yaml
	# Use argo.submit target
	${make} argo.submit/demos/data/argo-job1.yaml 
	# Submit job from file
	cat demos/data/argo-job1.yaml | ${argo.submit.stdin}
	# Inlined jobs + streams
	${mk.def.read}/argo.wf.template | ${argo.submit.stdin}
	# Inlines + manual managagement of tmp files 
	$(call io.mktemp) \
		&& ${mk.def.to.file}/argo.wf.template/$${tmpf} \
		&& ${make} argo.submit/$${tmpf} 
	# Third way: Submit job from URL
	url="${argo.app_url}" ${make} argo.submit.url

# Embedded workflow definition.  
# Using inlines is optional for experiments or one-offs
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