#!/usr/bin/env -S make -f
# S3-Compatible object storage with minio.
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/minio.mk clean create deploy test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/minio/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})

## Cluster lifecycle basics.  These are the same for most demos.

cluster.name=minio
minikube.args=--driver=docker -v1 --wait=all --embed-certs \

__main__: init clean create deploy test

init:

clean: stage/clean minikube.delete/${cluster.name}

wait: k8s.pods.wait

test: wait minio.create_buckets
create: stage/create minikube.get_or_create/${cluster.name}

deploy: stage/deploy infra.setup wait

## Minio details and setup.  
## This uses helm via ansible for idempotent operations, 
## honoring the minio_user/minio_password variables already setup.
## Helm blocks, then after setup is complete, kubefwd forwards the port.
export minio_user=minio_user
export minio_password=minio_password
export kubefwd_mapping="9000:9000"

infra.setup: minio.setup minio.fwd minio.create_buckets
minio.fwd: kubefwd.start/default/minio-s3
minio.stop: kubefwd.stop/default/minio-s3
minio.setup:; $(call \
    ansible_tasks, \
    -e minio_user=${minio_user} \
    -e minio_password=${minio_password})
define minio.setup
- name: Install MinIO Helm chart
  kubernetes.core.helm:
    name: minio-s3
    chart_ref: minio
    chart_repo_url: https://charts.min.io/
    release_namespace: default
    state: present
    # force: true
    create_namespace: true
    values:
      resources:
      requests:
        memory: 512Mi
      replicas: 1
      persistence:
        enabled: false
      mode: standalone
      rootUser: "{{minio_user}}"
      rootPassword: "{{minio_password}}"
endef

# After minio is setup, you can interact with it using aws CLI.
export AWS_ACCESS_KEY_ID=${minio_user}
export AWS_SECRET_ACCESS_KEY=${minio_password}
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL_S3=http://minio-s3:9000

# Use the awscli container for bucket ops just in case 
# host does not have the tool, or isn't using the canonical version.
minio.create_buckets:; $(call compose.bind.script, awscli)
define minio.create_buckets:
set -x
aws configure set default.s3.signature_version s3v4
aws s3 ls
aws s3 mb s3://my-bucket
aws s3 ls
endef