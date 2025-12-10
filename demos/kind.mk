#!/usr/bin/env -S make -f
# Demonstrate explicit/manual cluster management with tool containers.
#
# USAGE: 
#	./demos/kind.mk clean create
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/clusters/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk
$(call compose.import, file=k8s-tools.yml)

# Ignore any kubeconfig in an environment and start fresh 
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})

# Main entrypoint
__main__: clean create 

# Cluster "clean" API from scripts that run in containers
clean:; $(call compose.bind.script, kind)
define clean
set -x 
kind delete cluster --name kind-demo || true
endef

# Cluster "create" API from scripts that run in containers
create:; $(call compose.bind.script, kind)
define create
set -x 
kind create cluster --name kind-demo --kubeconfig ${KUBECONFIG}
endef

