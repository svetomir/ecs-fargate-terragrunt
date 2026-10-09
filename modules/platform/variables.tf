variable "name" {
  description = "Name for the cluster and the load balancer, for example ecs-fargate-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC the load balancer lives in."
  type        = string
}

variable "vpc_cidr" {
  description = "Address range of the VPC. The load balancer may only open connections into it."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the load balancer, one per zone and at least two."
  type        = list(string)
}

variable "ingress_cidrs" {
  description = "Source ranges allowed to reach the load balancer on port 80."
  type        = list(string)
}

variable "deletion_protection" {
  description = "True blocks deleting the load balancer until this is turned off."
  type        = bool
}

variable "log_retention_days" {
  description = "Days CloudWatch keeps the load balancer's access logs and the cluster's event and action logs."
  type        = number
}

variable "default_capacity_provider" {
  description = "Capacity a service or one-off task gets if it does not state its own: FARGATE or FARGATE_SPOT."
  type        = string
}

variable "container_insights" {
  description = "True turns on CloudWatch Container Insights for the cluster."
  type        = bool
}
