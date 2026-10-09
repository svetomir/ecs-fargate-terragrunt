output "arn" {
  description = "ARN of the secret. Consumers reference this, never the value."
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "Name of the secret."
  value       = aws_secretsmanager_secret.this.name
}
