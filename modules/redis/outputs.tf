output "primary_endpoint_address" {
  description = "DNS name that always points at the current primary, including after a failover."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Port Redis listens on."
  value       = local.port
}

output "auth_token_secret_arn" {
  description = "ARN of the secret holding the AUTH token. Clients reference this, never the value."
  value       = aws_secretsmanager_secret.auth.arn
}

output "client_security_group_id" {
  description = "Security group to attach to anything that needs to reach Redis."
  value       = aws_security_group.client.id
}
