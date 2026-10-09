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

  # A primary and one replica in different zones. Two nodes turn on automatic
  # failover and Multi-AZ. Not a burstable type, so performance is steady.
  node_type          = "cache.m7g.large"
  num_cache_clusters = 2

  # A week of daily backups, one last snapshot if the group is ever deleted,
  # and changes wait for the maintenance window.
  snapshot_retention_limit  = 7
  final_snapshot_identifier = "${include.root.locals.name_prefix}-redis-final"
  apply_immediately         = false

  # Both in UTC and in quiet hours. The snapshot finishes before maintenance can
  # start, so the two never overlap.
  snapshot_window    = "01:00-02:00"
  maintenance_window = "sun:03:00-sun:04:00"

  # The engine log and slow log are kept for 90 days.
  log_retention_days = 90

  # The AUTH token's secret is kept for 30 days after a delete, so a mistaken
  # destroy can be undone.
  auth_secret_recovery_window_in_days = 30
}
