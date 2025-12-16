#!/usr/bin/env -S make -f
# Demonstrate cluster management with API.
#
# USAGE: 
#	./demos/kind-2.mk clean create
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/clusters/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk

# Setup scaffolding for tool containers 
# Ignore any kubeconfig in an environment and start fresh 
$(call compose.import, file=k8s-tools.yml)
$(call mk.declare, K8S_PROJECT_LOCAL_CLUSTER)

cluster.name=kind-demo
__main__: clean create 

# Chain to clean from existing API primitives
clean: kind.delete/${cluster.name}
create: kind.get_or_create/${cluster.name}