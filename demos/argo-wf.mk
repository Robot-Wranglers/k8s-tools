####################################################################################
# demos/argo-wf.mk: 
#   Automation for a self-contained argo-workflows cluster with k8s-tools.git.
#   This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
#   interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#   
#   This demo ships with the `k8s-tools` repository and runs as part of the test-suite.
#
#   See the documentation here[1] for more discussion.
#
#   USAGE: 
#
#     # Default runs clean, create, deploy, test, but does not tear down the cluster
#     make -f demos/argo-wf.mk
#
#     # End-to-end, again without teardown 
#     make -f demos/argo-wf.mk clean create deploy test
#
#     # Finally, teardown the cluster
#     make -f demos/argo-wf.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools
####################################################################################

include k8s.mk

.DEFAULT_GOAL := demo.argo.workflows 

# Ensure local KUBECONFIG exists & ignore anything from environment
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

# Override k8s-tools.yml service-defaults, 
# explicitly setting the k3d version used
export K3D_VERSION:=v5.6.3

# Cluster details that will be used by k3d.
export CLUSTER_NAME:=k8s-tools-argowf

# https://argoproj.github.io/argo-events/quick_start/
argo_namespace=argo
argo_workflows_version="v3.6.4"
argo_app_url=https://raw.githubusercontent.com/argoproj/argo-workflows/main/examples/hello-world.yaml
argo_infra_url=https://github.com/argoproj/argo-workflows/releases/download/${argo_workflows_version}/quick-start-minimal.yaml

# Generate target-scaffolding for k8s-tools.yml services
$(eval $(call compose.import, ▰, TRUE, k8s-tools.yml))

# Default target should do everything, end to end.
demo.argo.workflows: clean create deploy test

# BEGIN: Top-level
###############################################################################

clean cluster.clean: flux.stage/cluster.clean ▰/k3d/k3d.cluster.delete/$${CLUSTER_NAME}	
create cluster.create: flux.stage/cluster.create ▰/k3d/k3d.cluster.get_or_create/$${CLUSTER_NAME}
wait cluster.wait: k8s.cluster.wait
deploy: flux.stage/deploy argo.wf.infra.setup
test: flux.stage/test argo.wf.infra.test argo.wf.app.test
teardown cluster.teardown: flux.stage/cluster.teardown 

# Public targets; these announce the automation stage and 
# then dispatch private targets in appropriate containers
argo.wf.infra.setup: flux.stage/argo.wf.infra.setup ▰/k8s/.argo.wf.infra.setup cluster.wait
argo.wf.infra.test: flux.stage/argo.wf.infra.test ▰/argo/.argo.wf.infra.test
argo.wf.app.test: flux.stage/argo.wf.app.test ▰/argo/.argo.wf.app.test

# Private targets; these handle the heavy lifting when tools are required.
.argo.wf.infra.setup: k8s.kubens.create/${argo_namespace}
	kubectl apply -f "${argo_infra_url}"
.argo.wf.infra.test: k8s.kubens/${argo_namespace}
	argo list
.argo.wf.app.test: k8s.kubens/${argo_namespace}
	@# Shows three ways to submit jobs
	${make} mk.def.read/argo.wf.template | ${make} stream.argo.submit
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/argo.wf.template/$${tmpf} \
	&& ${make} argo.submit/$${tmpf}
	url="${argo_app_url}" \
		${make} argo.submit.url

# BEGIN: Embedded data
###############################################################################

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
