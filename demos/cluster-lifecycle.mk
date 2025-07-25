#!/usr/bin/env -S make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Demonstrating full cluster lifecycle automation with k8s-tools.git.
# This exercises `compose.mk`, `k8s.mk`, plus the `k8s-tools.yml` services to 
# interact with a small k3d cluster.  Verbs include: create, destroy, deploy, etc.
#
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/cluster-lifecycle.mk clean create deploy test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/cluster-lifecycle
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Boilerplate section.
# Ensures local KUBECONFIG exists & ignores anything from environment
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

cluster.name=lifecycle-demo

clean: stage/cluster.clean k3d.cluster.delete/${cluster.name}
create: stage/cluster.create k3d.cluster.get_or_create/${cluster.name}
wait: k8s.cluster.wait
test: stage/cluster.test infra.test app.test

# Local cluster details and main automation.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

pod_name=test-harness
pod_namespace=default

# Main deployment entrypoint: First, announce the stage, then wait for cluster 
# to be ready.  Then run a typical example operation with helm with retries,
# then setup labels and a test-harness, and the prometheus stack
deploy: \
	stage/deploy \
	flux.retry/3/deploy.helm \
	deploy.test_harness \
	deploy.labels \
	deploy.grafana


deploy.labels:
	@# Add a random label to the default namespace
	kubectl label namespace default foo=bar

# Run a typical deployment with helm.  Using `helm` directly is 
# possible, but ansible is often nicer for idempotent operations.
# This uses a container and can be called directly from the host.. 
# so there is no need to install ansible *or* helm.  For more 
# direct usage, see the grafana deploy later in this file.
deploy.helm:
	${json.from} name=ahoy \
		chart_ref=hello-world \
		release_namespace=default \
		chart_repo_url="https://helm.github.io/examples" \
	| ${make} ansible.helm 

# Here `deploy.test_harness` has a public interface chaining to a "private" 
# target for internal use. The public interface just runs the private one 
# inside the `k8s` container, which makes it safe to use `kubectl` directly 
# even though it might not be present on the host.  The cluster should be 
# already setup but we retry a maximum of 3 times anyway just for illustration
# purposes.
deploy.test_harness: flux.retry/3/k8s.dispatch/self.test_harness.deploy
self.test_harness.deploy: \
	k8s.kubens.create/${pod_namespace} \
	k8s.test_harness/${pod_namespace}/${pod_name} \
	kubectl.apply/demos/data/nginx.svc.yml

# Simulate some infrastructure testing after setup is done. 
# This just shows the cluster's pod/service topology
infra.test:
	label="Showing kubernetes status" \
		${make} io.print.banner k8s.stat 
	label="Previewing topology for default namespace" \
		${make} io.print.banner k8s.graph.tui/default/pod
	label="Previewing topology for kube-system namespace" \
		${make} io.print.banner k8s.graph.tui/kube-system/pod

# Simulate some application testing after setup is done. 
# This pulls data from a pod container deployed to the cluster,
# shows an overview of whatever's already been deployed with helm.
app.test:
	label="Demo pod connectivity" ${make} io.print.banner
	echo uname -n | ${make} kubectl.exec.pipe/${pod_namespace}/${pod_name}
	label="Helm Overview" ${make} io.print.banner helm.stat

# Grafana setup and other optional, more interactive stuff that's part of
# the demo documentation.  User can opt-in and walk through this part manually
# We include the grafana.ini below just to demonstrate passing custom values
# to the helm chart.  For more configuration details see kube-prom-stack[1],
# grafana's docs [2].  More substantial config here might involve custom 
# dashboarding with this [3] 
#
# [1] https://github.com/prometheus-community/helm-charts
# [2] https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/
# [3] https://docs.ansible.com/ansible/latest/collections/grafana/grafana/dashboard_module.html
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Custom values to pass to helm, just to show we can. 
# See `deploy.grafana` for usage, see [2] for docs
define grafana.helm.values
grafana:
  grafana.ini:
    analytics:
      check_for_updates: false
    grafana_net:
      url: https://grafana.net
    log:
      mode: console
    paths:
      data: /var/lib/grafana/
      logs: /var/log/grafana
      plugins: /var/lib/grafana/plugins
      provisioning: /etc/grafana/provisioning
endef

# NB: Default password is preset by the charts. Real usage should override 
# but with grafana, your best bet is jumping straight into oauth. There are
# more than 5 years of github issues and forum traffic about fixes, regressions, 
# conflicting info and general confusion for setting non-default admin passwords 
# programmatically.  Want an experimental setup that avoids auth completely? 
# Those docs are also lies!
grafana.password=prom-operator
grafana.port_map=80:${grafana.host_port}
grafana.host_port=8089
grafana.url_base=http://grafana:${grafana.host_port}
grafana.chart.version=72.2.0
grafana.chart.url=https://prometheus-community.github.io/helm-charts
grafana.namespace=monitoring
grafana.pod_name=prometheus-stack-grafana

# Deployment for grafana.  Use helm directly this time instead of via ansible.
# Since the host might not have `helm` or not be using a standard version, we
# run inside the helm container.  Note the usage of `grafana.helm.values` to 
# provide custom values to helm, without any need for an external file.
deploy.grafana:; $(call containerized.maybe, helm)
.deploy.grafana: stage/Grafana k8s.kubens.create/${grafana.namespace}
	$(call io.log, ${bold}Deploying Grafana)
	( helm repo add prometheus-community ${grafana.chart.url} \
	  && helm repo update \
	  && ${mk.def.read}/grafana.helm.values | ${stream.peek} \
		| helm install prometheus-stack \
			prometheus-community/kube-prometheus-stack \
			--namespace ${grafana.namespace} --create-namespace \
			--version ${grafana.chart.version} \
			--values /dev/stdin \
		&& ${make} helm.stat ) | ${stream.as.log}

# Starts port-forwarding for grafana webserver. Working external DNS from host
fwd.grafana:
	kubefwd_mapping="${grafana.port_map}" ${make} kubefwd.start/${grafana.namespace}/${grafana.pod_name}
	$(call io.log, Connect with: http://admin:prom-operator@grafana:${grafana.host_port}\n)
fwd.grafana.stop: kubefwd.stop/stop/${grafana.namespace}/${grafana.pod_name}


# Runs all the grafana tests, some from inside the cluster, some from outside.
test.grafana: test.grafana.basic test.grafana.api 

# Another public/private pair of targets.
# The public one is safe to run from the host, and just calls the private target 
# from inside a tool container.  Since `.test.grafana.basic` runs in a container, 
# it's safe to use kubectl (and lots of other tools) without assuming they are 
# available on the host.  Also note the usage of `k8s.kubens/..` prerequisite to 
# set the kubernetes namespace that's used for the rest of the target body.
test.grafana.basic:; $(call containerized.maybe, kubectl)  
.test.grafana.basic: k8s.kubens/monitoring
	kubectl get pods

# Tests the grafana webserver and API, using the default authentication,
# from the host.  Note that this requires kubefwd tunnel has already been 
# setup using the `fwd.grafana` target, and that the docker-host actually 
# has curl!  First request grabs cookies for auth and the second uses them.
test.grafana.api:
	$(call io.log, ${bold}Testing Grafana API)
	${io.mktemp} \
	&& curl -sS -c $${tmpf} -X POST ${grafana.url_base}/login \
		-H "Content-Type: application/json" \
		-d '{"user":"admin", "password":"${grafana.password}"}' \
	&& curl -sS -b $${tmpf} ${grafana.url_base}/api/search \
		| ${jq} '.[]|select(.title|contains("Prometheus"))' \
		| ${stream.as.log}

# Opens an interactive shell into the test-pod.
# This requires that `deploy.test_harness` has already run.
cluster.shell: wait k8s.pod.shell/${pod_namespace}/${pod_name}
