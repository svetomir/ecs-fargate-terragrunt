# Two roles with different users:
#   execution - used by ECS itself to start the task: fetch secrets, write logs.
#   task      - used by the application code once it is running.

locals {
  # Every secret a task is handed when it starts.
  secret_arns = concat(values(var.secrets), local.uses_redis ? [var.redis.auth_secret_arn] : [])

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

# Write to this service's log group and nowhere else.
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
# AUTH token for the startup check. A policy with an empty resource list is not
# valid, so it is left out for a service with no secrets at all.
resource "aws_iam_role_policy" "execution_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  name = "read-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = local.secret_arns
    }]
  })
}

# Pull the image from the private ECR repositories the caller names. A public
# image needs no permission, so the policy is left out when there are none. The
# Redis check's image is public either way.
resource "aws_iam_role_policy" "execution_pull" {
  count = length(var.ecr_repository_arns) > 0 ? 1 : 0

  name = "pull-images"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Signing in to the registry. AWS does not let this action be limited to a
      # repository; the three below are.
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = var.ecr_repository_arns
      },
    ]
  })
}

# The application calls no AWS APIs, so its role has no permissions. It exists so
# that a caller can attach some later without touching this module.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = local.ecs_tasks_trust_policy
}
