#!/usr/bin/env -S make -f
# Several ways to work with ansible, part 1.
# Demonstrating direct execution of a task-list, without a playbook.
#
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/ansible.mk clean create deploy 
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/ansible/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Cluster lifecycle basics and other boilerplate. (The same for most demos)
include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(call compose.import, file=k8s-tools.yml)

$(eval $(call k8s.scaffold.cluster, \
  name=ansible \
  template=minikube \
  args='--driver=docker -v1 --wait=all --embed-certs'))

__main__: clean create deploy 
deploy: my_ansible_tasks

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

my_ansible_tasks:
	$(call ansible_tasks, -e extra=Variables -e are=allowed)
define my_ansible_tasks
- name: "{{extra}} {{are}} in tasks."
  kubernetes.core.helm:
    name: ahoy
    chart_ref: hello-world
    release_namespace: default
    chart_repo_url: "https://helm.github.io/examples"
endef