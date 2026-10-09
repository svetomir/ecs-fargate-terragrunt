locals {
  port = 6379

  # Failover needs a replica to fail over to, so both settings follow the node count.
  has_replica = var.num_cache_clusters > 1
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis for ${var.name}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = local.port

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.has_replica
  multi_az_enabled           = local.has_replica

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Clients must present this token after connecting. See auth.tf.
  auth_token_wo         = ephemeral.aws_secretsmanager_secret_version.auth.secret_string
  auth_token_wo_version = var.auth_token_version

  snapshot_retention_limit  = var.snapshot_retention_limit
  final_snapshot_identifier = var.final_snapshot_identifier
  apply_immediately         = var.apply_immediately

  # When the daily snapshot is taken and when AWS may apply maintenance, both in
  # UTC. Null leaves the choice to AWS.
  snapshot_window    = var.snapshot_window
  maintenance_window = var.maintenance_window

  log_delivery_configuration {
    log_type         = "engine-log"
    destination_type = "cloudwatch-logs"
    destination      = aws_cloudwatch_log_group.engine_log.name
    log_format       = "json"
  }

  log_delivery_configuration {
    log_type         = "slow-log"
    destination_type = "cloudwatch-logs"
    destination      = aws_cloudwatch_log_group.slow_log.name
    log_format       = "json"
  }

  # The delivery service must already be allowed to write when delivery is set up.
  depends_on = [aws_cloudwatch_log_resource_policy.redis_logs]
}
