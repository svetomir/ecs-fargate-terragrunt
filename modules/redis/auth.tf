# The Redis AUTH token.
#
# Secrets Manager holds the only copy. The token is generated in memory, written
# to the secret, read back in memory and handed to ElastiCache. Each step uses an
# ephemeral value or a write-only (`_wo`) argument, so the token is never in the
# plan or the state.
#
# ElastiCache is given the value read back from the secret, not the generated one.
# If an apply fails part way and is run again, a new value is generated, but the
# secret is not rewritten, so ElastiCache still receives the token that is stored.

ephemeral "random_password" "auth" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "auth" {
  name                    = "${var.name}/redis/auth-token"
  description             = "AUTH token for the ${var.name} Redis replication group"
  recovery_window_in_days = var.auth_secret_recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id = aws_secretsmanager_secret.auth.id

  secret_string_wo         = ephemeral.random_password.auth.result
  secret_string_wo_version = var.auth_token_version
}

# Refers to the version above, not only to the secret, so the value is read
# after it has been written.
ephemeral "aws_secretsmanager_secret_version" "auth" {
  secret_id = aws_secretsmanager_secret_version.auth.secret_id
}
