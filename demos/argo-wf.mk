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
#   # Default runs clean, create, deploy, test, but does not tear down the cluster
#   ./demos/argo-wf.mk
#
#   # End-to-end, again without teardown 
#   ./demos/argo-wf.mk clean create deploy test
#
#   # Finally, teardown the cluster
#   ./demos/argo-wf.mk teardown
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
include k8s.mk
cluster.name=argo-wf
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})
$(eval $(call compose.import, k8s-tools.yml))
__main__: clean create deploy test

# Cluster lifecycle basics.  These are similar for all demos, 
# and mostly just setting up aliases for existing targets. 
# The `flux.stage` usage announces sections, `k3d.*` are library calls.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

clean cluster.clean teardown cluster.teardown: \
	flux.stage/cluster.clean k3d.cluster.delete/${cluster.name}
create cluster.create: \
	flux.stage/cluster.create k3d.cluster.get_or_create/${cluster.name}
wait cluster.wait: k8s.cluster.wait
test cluster.test: flux.stage/test.cluster cluster.wait infra.test app.test

# Local cluster details
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

argo.namespace=argo
argo.workflows_version="v3.6.4"
argo.repo=https://github.com/argoproj/argo-workflows
argo.repo_raw=https://raw.githubusercontent.com/argoproj/argo-workflows
argo.app_url=${argo.repo_raw}/main/examples/hello-world.yaml
argo.infra_url=${argo.repo}/releases/download/${argo.workflows_version}/quick-start-minimal.yaml

deploy cluster.deploy: \
	flux.stage/cluster.deploy \
	flux.loop.until/k8s.cluster.ready \
	infra.setup

# Dispatches the private-target inside a container, 
# then waits for the cluster to settle.
infra.setup: argo.dispatch/.infra.setup cluster.wait
.infra.setup: k8s.kubens.create/${argo.namespace}
	kubectl apply -f ${argo.infra_url} | ${stream.as.log}

# Show details about post-deploy pod/service topology,
# Uses context-managers for namespaces, and lists known workflows.
infra.test: argo.dispatch/.infra.test
	label="Previewing topology for argo namespace" \
		${make} io.print.banner k8s.graph.tui/${argo.namespace}/pod
.infra.test: k8s.kubens/${argo.namespace} argo.list

# Shows many different ways to submit jobs
app.test: argo.dispatch/.app.test
.app.test: k8s.kubens/${argo.namespace}
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