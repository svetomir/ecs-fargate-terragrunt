# Two roles with different users:
#   execution - used by ECS itself to start the task: fetch secrets, write logs.
#   task      - used by the application code once it is running.

locals {
  # Both roles can only be assumed by ECS tasks.
  ecs_tasks_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = local.ecs_tasks_trust_policy
}

# Write to this service's log group and nowhere else. Both images are public, so
# no registry permissions are needed.
resource "aws_iam_role_policy" "execution_logs" {
  name = "write-logs"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.this.arn}:*"
    }]
  })
}

# Read exactly the secrets the task uses: the application's own, and the Redis
# AUTH token for the startup check.
resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = concat(values(var.secrets), [var.redis_auth_secret_arn])
    }]
  })
}

# The application calls no AWS APIs, so its role has no permissions. It exists so
# that a caller can attach some later without touching this module.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = local.ecs_tasks_trust_policy
}
