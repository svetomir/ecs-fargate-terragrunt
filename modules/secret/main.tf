# The value is generated during apply and handed straight to Secrets Manager.
# An `ephemeral` value exists only in memory for the run, and a write-only (`_wo`)
# argument is never saved, so the value appears in neither the plan nor the state.
ephemeral "random_password" "this" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id

  # Terraform cannot compare a value it never stores, so the version number is
  # what tells it to write a new one.
  secret_string_wo         = ephemeral.random_password.this.result
  secret_string_wo_version = var.value_version
}
