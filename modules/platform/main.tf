# What every service in an environment shares: the cluster they run in (this file)
# and the load balancer they sit behind (alb.tf).

# The account and region in use, needed to write ARNs in events.tf and
# log_permissions.tf.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

# Makes both Fargate capacity types available. Each service states the one it
# wants; the default is what a service or one-off task gets if it states none.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.default_capacity_provider
    weight            = 1
  }
}
