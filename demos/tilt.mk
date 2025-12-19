#!/usr/bin/env -S make -f
# Working with Tilt and Tiltfiles, part 1.
# Cluster Management + External Tiltfile
#   
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/tilt.mk clean create deploy test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/tilt/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include .cmk/compose.mk
include k8s.mk
export KUBECONFIG:=./local.cluster.yml
export TILT_PORT=10351

$(shell umask 066; touch ${KUBECONFIG})
$(call compose.import, file=k8s-tools.yml)

## Cluster lifecycle basics.  These are the same for most demos.

__main__: clean create deploy test

cluster.name=tilt
minikube.args=\
  --driver=docker -v1 --wait=all --embed-certs

wait: k8s.wait
clean: stage/clean minikube.delete/${cluster.name}
create: stage/create minikube.get_or_create/${cluster.name}

## Tilt specifics 
deploy: stage/deploy tilt.serve/demos/data/Tiltfile io.wait/7 
test: tilt.get_logs/100
