#!/usr/bin/env -S make -f
# S3-Compatible object storage with minio.
#
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/minio.mk clean create deploy test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/minio/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include k8s.mk
export KUBECONFIG:=./local.cluster.yml
$(shell umask 066; touch ${KUBECONFIG})
$(call compose.import, file=k8s-tools.yml)

## Cluster lifecycle basics.  These are the same for most demos.

cluster.name=terraform
minikube.args=--driver=docker -v1 --wait=all --embed-certs \

__main__: init clean create deploy test

clean: stage/clean minikube.delete/${cluster.name}
create: stage/create minikube.get_or_create/${cluster.name}
wait: k8s.pods.wait
test: terraform.test
deploy: stage/deploy infra.setup wait

##

infra.setup:
terraform.test:; $(call terraform_tasks)
define terraform.test
terraform {}
variable "KUBECONFIG" {
  type    = string
  default = "~/.kube/config"  # or leave empty
}
provider "kubernetes" {
  config_path = var.KUBECONFIG
}
data "kubernetes_namespace" "kube_system" {
  metadata { name = "kube-system" }
}
data "kubernetes_namespace" "default" {
  metadata { name = "default" }
}
output "connection_test" {
  description = "Basic connection test to verify Terraform can access the cluster"
  value = {
    kube_system_namespace = data.kubernetes_namespace.kube_system.metadata[0].name
    default_namespace     = data.kubernetes_namespace.default.metadata[0].name
    connection_status     = "SUCCESS - Terraform can access the cluster"
  }
}
resource "random_id" "job_suffix" {
  byte_length = 4
}
resource "kubernetes_job" "demo_job" {
  metadata {
    name      = "terraform-demo-job-${random_id.job_suffix.hex}"
    namespace = "default"
    labels = {
      app     = "terraform-demo"
      type    = "job-demo"
      managed = "terraform"
    }
  }
  spec {
    template {
      metadata {
        labels = { app = "terraform-demo-job" }
      }
      spec {
        container {
          name  = "demo-job-container"
          image = "busybox:latest"
          command = [
            "/bin/sh",
            "-c",
            "echo 'Hello from Terraform Kubernetes Job!'; echo 'Job started at:'; date; sleep 30; echo 'Job completed at:'; date"
          ]
        }
        restart_policy = "Never"
      }
    }
  }
  wait_for_completion = true
}
output "job_information" {
  description = "Information about the created job"
  value = {
    job_name = kubernetes_job.demo_job.metadata[0].name
    job_uid  = kubernetes_job.demo_job.metadata[0].uid
  }
}
endef

# # Output node capacity summary
# output "node_capacity_summary" {
#   description = "Summary of node capacities"
#   value = {
#     for node in data.kubernetes_nodes.all_nodes.nodes : node.metadata[0].name => {
#       cpu = node.status[0].capacity.cpu
#       memory = node.status[0].capacity.memory
#       pods = node.status[0].capacity.pods
#       storage = try(node.status[0].capacity["ephemeral-storage"], "N/A")
#     }
#   }
# }

# # Output ready nodes only
# output "ready_nodes" {
#   description = "List of nodes that are in Ready state"
#   value = [
#     for node in data.kubernetes_nodes.all_nodes.nodes : node.metadata[0].name
#     if contains([
#       for condition in node.status[0].conditions : condition.status
#       if condition.type == "Ready"
#     ], "True")
#   ]
# }