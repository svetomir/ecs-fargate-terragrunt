include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules//platform"
}

dependency "network" {
  config_path = "../network"

  # Placeholders so this unit can be planned before the network has been applied.
  # They are only allowed for the commands listed; apply needs the real outputs.
  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    vpc_cidr_block = "10.1.0.0/16"
    public_subnets = ["subnet-00000000000000011", "subnet-00000000000000012", "subnet-00000000000000013"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name       = include.root.locals.name_prefix
  vpc_id     = dependency.network.outputs.vpc_id
  vpc_cidr   = dependency.network.outputs.vpc_cidr_block
  subnet_ids = dependency.network.outputs.public_subnets

  # Prod is open to the internet.
  ingress_cidrs = ["0.0.0.0/0"]

  # The load balancer's access logs and the cluster's event and action logs are
  # kept for 90 days.
  log_retention_days = 90

  # Anything that does not state its own capacity runs on on-demand.
  default_capacity_provider = "FARGATE"

  # The load balancer cannot be deleted by accident, and the cluster reports
  # per-task CPU, memory and network metrics.
  deletion_protection = true
  container_insights  = true
}
