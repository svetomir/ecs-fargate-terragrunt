include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules//redis"
}

dependency "network" {
  config_path = "../network"

  # Placeholders so this unit can be planned before the network has been applied.
  # They are only allowed for the commands listed; apply needs the real outputs.
  mock_outputs = {
    vpc_id        = "vpc-00000000000000000"
    intra_subnets = ["subnet-00000000000000021", "subnet-00000000000000022", "subnet-00000000000000023"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name   = include.root.locals.name_prefix
  vpc_id = dependency.network.outputs.vpc_id

  # The data subnets: no route to the internet.
  subnet_ids = dependency.network.outputs.intra_subnets

  # A single small node: no replica, so no failover and no Multi-AZ.
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1

  # No backups, and changes take effect straight away.
  snapshot_retention_limit = 0
  apply_immediately        = true

  # The engine log and slow log are kept for a week.
  log_retention_days = 7

  # The AUTH token's secret is deleted at once on destroy, so dev can be torn down
  # and recreated under the same name.
  auth_secret_recovery_window_in_days = 0
}
