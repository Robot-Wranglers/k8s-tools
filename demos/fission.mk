#!/usr/bin/env -S stdbuf -o0 -e0 make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Demo a self-contained functions-as-a-service with k3d, fission, & k8s-tools.git.
# This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
# interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#
#   # Default entrypoint runs clean, create, deploy, 
#   # and tests, but does does not tear down the cluster.  
#   ./demos/fission.mk
#
#   # End-to-end, again without teardown 
#   ./demos/fission.mk clean create deploy test
#
#   # Finally, teardown the cluster
#   ./demos/fission.mk teardown
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/faas
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Boilerplate.  
# Ensures local KUBECONFIG exists & ignore anything from environment
# Sets cluster details that will be used by k3d.
# Generates target-scaffolding for k8s-tools.yml services
# Setup the default target that will do everything, end to end.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})
$(call compose.import, file=k8s-tools.yml)
__main__: clean create deploy test

# Cluster lifecycle basics.  These are similar for all demos, 
# and mostly just setting up CLI aliases for existing targets. 
# The `stage` are just announcing sections, `k3d.*` are library calls.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

cluster.name:=fission

clean: stage/cluster.clean k3d.cluster.delete/${cluster.name}
	@# Clean up cluster
create: stage/cluster.create k3d.cluster.get_or_create/${cluster.name}
	@# Begin 'create' stage; setup cluster

deploy: stage/deploy infra.setup app.setup
	@# Begin 'deploy' stage, setup infra and apps

test: infra.test wait app.test
	@# Test all infrastructure and apps
wait: k8s.cluster.wait

shell: fission.shell
	@# Drops into an interactive shell for the fission container.
	@# Shell inherits this environment, i.e. KUBECONFIG is already configured
	
# Local cluster details
#  - https://fission.io/docs/installation/
#  - https://fission.io/docs/reference/fission-cli/fission_token_create/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

fission.namespace=fission
fission.url=https://github.com/fission/fission/releases/download/v1.21.0/fission-all-v1.21.0-minikube.yaml

infra.setup: stage/infra.setup k8s.dispatch/.infra.setup wait
	@# Bootstrap infrastructure and wait till cluster settles
.infra.setup: k8s.kubens.create/${fission.namespace}
	(kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.21.0" 2>&1 || true) \
		| ${stream.as.log}
	url="${fission.url}" ${make} kubectl.apply.url
		${make} k8s.kubens/default

infra.test: stage/infra.test fission.stat
app.setup: stage/app.setup infra.test app.deploy wait
	@# Ensure infrastructure is ready, deploy app, wait for cluster to settle

app.deploy: stage/app.deploy fission.dispatch/.app.deploy
	@# Install the application components if they aren't installed
.app.deploy: k8s.kubens/default 
	img=fission/python-env ${make} fission.env.create/python
	export fission_env=python \
	&& export fission_code=demos/data/src/fission/app.py \
	&& ${make} .fission.function.create/fission-app

app.test: stage/app.test k8s.wait fission.dispatch/.app.test
	@# Tests the application deployment by running a function
.app.test: k8s.kubens/default fission.stat
	set -x && fission function test --timeout=0 --name fission-app

