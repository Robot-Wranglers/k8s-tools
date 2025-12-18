#!/usr/bin/env -S make -f
# Demonstrating multicluster networking with minikube, calico, 
# and submariner.  Verbs include: create, destroy, deploy, etc.
#   
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/istio.mk clean create deploy test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/istio/
#   [2] https://istio.io/latest/docs/setup/install/helm/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include .cmk/compose.mk 
include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})

$(call compose.import, file=k8s-tools.yml)
__main__: clean create deploy test

minikube.args=--driver=docker --cni=calico -v1 --wait=all --embed-certs
cluster.name=istio

clean: stage/clean minikube.delete/${cluster.name}
wait: k8s.pods.wait
test: wait test.infra test.app
create: stage/create minikube.get_or_create/${cluster.name}
deploy: stage/deploy infra.setup wait app.setup wait

# Infrastructure entrypoints
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

export istio_chart=https://istio-release.storage.googleapis.com/charts
export istio_namespace=istio-system

# Infrastructure setup.  Use `helm` to setup istio
# NB: for idempotence use instead `ansible.helm` --
# this is just to demonstrate using `compose.bind.script`
infra.setup:; $(call compose.bind.script, svc=k8s env='istio_chart istio_namespace')
define infra.setup
set -x
helm repo add istio ${istio_chart}
helm repo update
helm install istio-base \
  istio/base -n ${istio_namespace} --wait \
  --set defaultRevision=default --create-namespace
helm install istiod istio/istiod -n ${istio_namespace} --wait
helm ls -n ${istio_namespace}
endef

# Test infrastructure by grabbing details 
# about a few things that were deployed.
test.infra: stage/test.infrastructure \
  istio.virtualservices/ab-testing \
	k8s.deployments/ab-testing k8s.pods/ab-testing \
	k8s.svc/ab-testing istio.validate/ab-testing

# Demonstrate idiom for calling a task in a container.
# Read manifests from this file using `mk.def.read`,
# then pipe data to kubectl apply.  This deploys the 
# flask app, wraps it in virtual service, then sets the 
# traffic policy
app.setup:; $(call compose.bind.target, k8s)
self.app.setup:
	$(call log.k8s, ${@} ${sep} Deploying application..)
	${mk.def.read}/base.manifest.yml | ${kubectl.apply.stdin}
	${mk.def.read}/services.manifest.yml | ${kubectl.apply.stdin}
	${make} app.traffic.policy/50,50

# Helper to set the traffic policy.  
# This accepts 2 arguments describing the split, e.g "50,50".
# This reads the traffic policy from this file, rewrites it, 
# reflecting the given arguments, then posts the changes to
# the cluster,all using pipes.
app.traffic.policy/%:; $(call compose.bind.target, k8s)
self.app.traffic.policy/%:
	$(call log.k8s, ${@} ${sep} Shift application traffic policy..)
	first=`echo ${*} | cut -d, -f1` \
	&& second=`echo ${*} | cut -d, -f2` \
	&& ${mk.def.read}/traffic.manifest.yml \
	| ${yq} -o json \
	| ${jq} ".spec.http[0].route[0].weight=$${first}" \
	| ${jq} ".spec.http[0].route[1].weight=$${second}" \
	| ${kubectl.apply.stdin}

# Run trials with the default traffic policy, 
# then change the policy and rerun the trials 
# just to confirm that the policy changed
test.app:; $(call compose.bind.target, k8s)
self.test.app: stage/test.application \
	k8s.test_harness/ab-testing/test-harness wait \
	app.run.trials app.run.trials/95,5

# Call the web-app repeatedly to get coin-flip data.
app.run.trials/%:; ${make} app.traffic.policy/${*} app.run.trials
	@# Shifts traffic policy, then runs trials.
app.run.trials:; $(call compose.bind.target, k8s)
self.app.run.trials:
	$(call log.k8s, ${@} ${sep} Testing traffic policy with trial requests..)
	num_trials=$${num_trials:-100} \
	&& result="`seq $${num_trials} \
	| xargs -I% echo curl -fsS coin-service.ab-testing.svc.cluster.local:8080 \
	| kubectl exec -i -n ab-testing test-harness -- bash`" \
	&& $(call k8s.log, Trials:) \
	&& printf "$${result}" | ${stream.fold} | ${stream.as.log} \
	&& heads=`printf "$${result}" | grep heads | ${stream.count.lines}` \
	&& tails=`printf "$${result}" | grep tails | ${stream.count.lines}` \
	&& ratio=`echo $${heads} / $${num_trials} | bc -l` \
	&& $(call k8s.log.part1, Heads) && $(call k8s.log.part2, $${heads}) \
	&& $(call k8s.log.part1, Tails) && $(call k8s.log.part2, $${tails}) \
	&& $(call k8s.log.part1, Ratio) && $(call k8s.log.part2, $${ratio})

# Embedded data
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define base.manifest.yml
# Enable automatic Istio sidecar injection
apiVersion: v1
kind: Namespace
metadata:
  name: ab-testing
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ConfigMap
metadata: {"name": "app-src-code", "namespace": "ab-testing"}
data:
  app.py: |
    from flask import Flask
    import os
    app = Flask(__name__)
    @app.route('/')
    def root():
        return f"{os.environ['COIN']}\n"
    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=8080)
---
endef

define traffic.manifest.yml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata: {"name": "coin-service-vs", "namespace": "ab-testing"}
spec:
  hosts: ["coin-service"]
  http:
  - route:
    - {"weight": 50, "destination": {"host": "alice-svc", "port": {"number": 8080}}}
    - {"weight": 50, "destination": {"host": "bob-svc", "port": {"number": 8080}}}
endef

define services.manifest.yml
apiVersion: apps/v1
kind: Deployment
metadata: {"name": "alice", "namespace": "ab-testing"}
spec:
  replicas: 1
  selector: {"matchLabels": {"app": "coin-service", "version": "alice"}}
  template:
    metadata: {"labels": {"app": "coin-service", "version": "alice"}}
    spec:
      containers:
      - name: alice
        image: python:3.9-slim
        ports: [{"containerPort": 8080}]
        env: [{"name": "COIN", "value": "heads"}]
        command: ["/bin/bash", "-c"]
        args: [ "pip install flask && python /app/app.py" ]
        volumeMounts: [{"name": "app-config-volume", "mountPath": "/app"}]
      volumes: [{"name": "app-config-volume", "configMap": {"name": "app-src-code"}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {"name": "bob", "namespace": "ab-testing"}
spec:
  replicas: 1
  selector: {"matchLabels": {"app": "coin-service", "version": "bob"}}
  template:
    metadata: {"labels": {"app": "coin-service", "version": "bob"}}
    spec:
      containers:
      - name: bob
        image: python:3.9-slim
        ports: [{"containerPort": 8080}]
        env: [{"name": "COIN", "value": "tails"}]
        command: ["/bin/bash", "-c"]
        args: [ "pip install flask && python /app/app.py" ]
        volumeMounts: [{"name": "app-config-volume", "mountPath": "/app"}]
      volumes: [{"name": "app-config-volume", "configMap": {"name": "app-src-code"}}]
---
apiVersion: v1
kind: Service
metadata: {"name": "alice-svc", "namespace": "ab-testing"}
spec: {"ports": [{"port": 8080, "name": "http"}], "selector": {"app": "coin-service", "version": "alice"}}
---
apiVersion: v1
kind: Service
metadata: {"name": "bob-svc", "namespace": "ab-testing"}
spec: {"selector": {"app": "coin-service", "version": "bob"}, "ports": [{"port": 8080, "name": "http"}]}
---
apiVersion: v1
kind: Service
metadata: {"name": "coin-service", "namespace": "ab-testing"}
spec: {"selector": {"app": "coin-service"}, "ports": [{"port": 8080, "name": "http"}]}
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata: {"name": "coin-service-dr", "namespace": "ab-testing"}
spec:
  host: coin-service
  subsets:
    - {"name": "alice", "labels": {"version": "alice"}}
    - {"name": "bob", "labels": {"version": "bob"}}
---
endef