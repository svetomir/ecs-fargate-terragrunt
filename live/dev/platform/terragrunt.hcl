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
    vpc_cidr_block = "10.0.0.0/16"
    public_subnets = ["subnet-00000000000000011", "subnet-00000000000000012", "subnet-00000000000000013"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name       = include.root.locals.name_prefix
  vpc_id     = dependency.network.outputs.vpc_id
  vpc_cidr   = dependency.network.outputs.vpc_cidr_block
  subnet_ids = dependency.network.outputs.public_subnets

  # Dev is not open to the internet: only these source ranges reach the load balancer.
  # 203.0.113.0/24 is reserved for documentation and routes nowhere, so dev stays
  # closed until this is replaced with the team's VPN or office range.
  ingress_cidrs = ["203.0.113.0/24"]

  # The load balancer's access logs and the cluster's event and action logs are
  # kept for a week.
  log_retention_days = 7

  # Anything that does not state its own capacity runs on Spot.
  default_capacity_provider = "FARGATE_SPOT"

  deletion_protection = false
  container_insights  = false
}
