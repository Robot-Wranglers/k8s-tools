#!/usr/bin/env -S make -f
# demos/istio.mk: 
#   Demonstrating multicluster networking with minikube, calico, 
#   and submariner.  Verbs include: create, destroy, deploy, etc.
#   
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
# Note that repeatedly setting up calico can quickly run into rate-limiting 
# with docker.io, and you might want to setup a local registry mirror [2]
#
# USAGE: 
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/istio/
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
$(shell mkdir -p ./.minikube)
$(eval $(call compose.import, k8s-tools.yml))
__main__: clean create deploy test

# Details for multi-cluster bootstrap.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

minikube.args=--driver=docker --network-plugin=cni --cni=calico -v1 --wait=all --embed-certs
cluster.name=istio
clean: stage/clean minikube.delete/${cluster.name}
wait: k8s.cluster.wait
test: stage/test wait test.infra test.app

create: \
	stage/create \
	minikube.cluster.get_or_create/${cluster.name} \
	flux.loop.until/k8s.cluster.ready

deploy: stage/deploy deploy.infra k8s.wait deploy.app k8s.wait
# https://istio.io/latest/docs/setup/install/helm/
deploy.infra:; $(call containerized.maybe, k8s)
.deploy.infra:
	$(call log.k8s, ${@} ${sep} Deploying istio base)
	set -x \
	&& helm repo add istio https://istio-release.storage.googleapis.com/charts \
	&& helm repo update \
	&& helm install istio-base istio/base \
		-n istio-system --set defaultRevision=default --create-namespace \
	&& ${make} kubectl.wait \
	&& helm ls -n istio-system \
	&& helm install istiod istio/istiod -n istio-system --wait \
	&& helm ls -n istio-system 
	$(call log.k8s, ${@} ${sep} Deploying istio site)

test.infra:; $(call containerized.maybe, istioctl)
.test.infra: 
	$(call log.k8s, ${@} ${sep} Testing infrastructure)
	${make} istio.virtualservices/ab-testing \
		k8s.deployments/ab-testing \
		k8s.pods/ab-testing \
		k8s.svc/ab-testing
	istioctl analyze

deploy.app:; $(call containerized.maybe, k8s)
.deploy.app:
	$(call log.k8s, ${@} ${sep} Deploying app)
	${mk.def.read}/services | ${kubectl.apply.stdin}
	${mk.def.read}/vservice | ${kubectl.apply.stdin}

shift.app:; $(call containerized.maybe, k8s)
.shift.app:
	$(call log.k8s, ${@} ${sep} shift traffic app)
	${mk.def.read}/shift | ${kubectl.apply.stdin} 

test.app:; $(call containerized.maybe, k8s)
.test.app: k8s.test_harness/ab-testing/test-harness k8s.wait
	$(call k8s.log.part1, Pulling clusterIP for coin service) \
	&& clusterIP=`kubectl get svc -n ab-testing coin-service -ojson|jq -re .spec.clusterIP` \
	&& $(call k8s.log.part2, $${clusterIP}) \
	&& ${make} ..test.app/$${clusterIP} \
	&& ${make} .shift.app \
	&& ${make} io.wait/10 \
	&& ${make} ..test.app/$${clusterIP} \

..test.app/%:
	num_trials=$${num_trials:-100} \
	&& result="`seq $${num_trials} \
	| xargs -I% echo curl -fsS ${*}:8080 \
	| kubectl exec -i -n ab-testing test-harness -- bash`" \
	&& $(call k8s.log,Trials:) \
	&& printf "$${result}" | ${stream.fold} | ${stream.as.log} \
	&& $(call k8s.log.part1, Heads) \
	&& heads=`printf "$${result}" | grep heads | wc -l` \
	&& $(call k8s.log.part2, $${heads}) \
	&& $(call k8s.log.part1, Tails) \
	&& tails=`printf "$${result}" | grep tails | wc -l` \
	&& $(call k8s.log.part2, $${tails}) \
	&& $(call k8s.log.part1, Ratio) \
	&& ratio=`echo $${heads} / $${num_trials}|bc -l` \
	&& $(call k8s.log.part2, $${ratio})

k8s.log=${log.k8s}

# curl http://<service-name>.<namespace>.svc.cluster.local/<path>

define services
### 1. Create namespace and enable Istio injection
# Create a namespace for our demo
apiVersion: v1
kind: Namespace
metadata:
  name: ab-testing
  labels:
    istio-injection: enabled  # Enable automatic Istio sidecar injection
---
# Alice ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-src-code
  namespace: ab-testing
data:
  app.py: |
    from flask import Flask
    import os
    app = Flask(__name__)
    @app.route('/')
    def root():
        return f"{os.environ['COIN']}\n"
    @app.route('/flip')
    def flip():
        return f"{os.environ['COIN']}\n"
    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=8080)
---
# Alice Service Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alice
  namespace: ab-testing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: coin-service
      version: alice
  template:
    metadata:
      labels:
        app: coin-service
        version: alice
    spec:
      containers:
      - name: alice
        image: python:3.9-slim
        ports: [{"containerPort": 8080}]
        env: [{"name": "COIN", "value": "heads"}]
        command: ["/bin/bash", "-c"]
        args: [ "pip install flask && python /app/app.py" ]
        volumeMounts:
          - name: app-config-volume
            mountPath: /app
      volumes:
        - name: app-config-volume
          configMap: {"name": "app-src-code"}
---
### 3. Deploy Bob Service (returns "tails")
# Bob Service Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bob
  namespace: ab-testing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: coin-service
      version: bob
  template:
    metadata:
      labels:
        app: coin-service
        version: bob
    spec:
      containers:
      - name: bob
        image: python:3.9-slim
        ports: [{"containerPort": 8080}]
        env: [{"name": "COIN", "value": "tails"}]
        command: ["/bin/bash", "-c"]
        args: [ "pip install flask && python /app/app.py" ]
        volumeMounts:
          - name: app-config-volume
            mountPath: /app
      volumes:
        - name: app-config-volume
          configMap: {"name": "app-src-code"}
---

### 4. Create Individual and Common Services
# Alice Service
apiVersion: v1
kind: Service
metadata:
  name: alice-svc
  namespace: ab-testing
spec:
  ports:
    - port: 8080
      name: http
  selector:
    app: coin-service
    version: alice
---
# Bob Service
apiVersion: v1
kind: Service
metadata:
  name: bob-svc
  namespace: ab-testing
spec:
  ports:
    - port: 8080
      name: http
  selector:
    app: coin-service
    version: bob
---
endef

define vservice
# Common Service that all external requests will go through
# This selects both alice and bob pods
apiVersion: v1
kind: Service
metadata:
  name: coin-service
  namespace: ab-testing
spec:
  ports:
  - port: 8080
    name: http
  selector:
    app: coin-service  
---

### 5. Istio VirtualService and DestinationRule
# VirtualService for traffic splitting
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: coin-service-vs
  namespace: ab-testing
spec:
  hosts: ["coin-service"]
  http:
  - route:
    - destination: {"host": "alice-svc"}
      weight: 50
    - destination: {"host": "bob-svc"}
      weight: 50
# DestinationRule for subset definition
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: coin-service-dr
  namespace: ab-testing
spec:
  host: coin-service
  subsets:
  - name: alice
    labels:
      version: alice
  - name: bob
    labels:
      version: bob
endef
define shift
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: coin-service-vs
  namespace: ab-testing
spec:
  hosts: ["coin-service"]
  http:
  - route:
    - destination:
        host: alice-svc
        port:
          number: 8080
      weight: 95
    - destination:
        host: bob-svc
        port:
          number: 8080
      weight: 5
endef