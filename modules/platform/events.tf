# ECS events: task, service and deployment state changes, kept in CloudWatch Logs.
#
# ECS itself only shows why a task stopped for about an hour. A task whose Redis
# check fails stops straight away, so this is where the reason and the exit code
# can still be found afterwards.

# EventBridge can only write to log groups whose name starts with /aws/events/.
resource "aws_cloudwatch_log_group" "ecs_events" {
  name              = "/aws/events/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

locals {
  # The ARN of every service in this cluster starts with this.
  service_arn_prefix = "arn:aws:ecs:${local.region}:${local.account_id}:service/${aws_ecs_cluster.this.name}/"
}

resource "aws_cloudwatch_event_rule" "ecs_events" {
  name        = "${var.name}-ecs-events"
  description = "State changes of tasks, services and deployments in the ${var.name} cluster"

  # An event matches if either line under "$or" does. Task and service events
  # carry the cluster's ARN. Deployment events only name the service.
  event_pattern = jsonencode({
    source = ["aws.ecs"]
    "$or" = [
      { detail = { clusterArn = [aws_ecs_cluster.this.arn] } },
      { resources = [{ prefix = local.service_arn_prefix }] },
    ]
  })
}

resource "aws_cloudwatch_event_target" "ecs_events" {
  rule = aws_cloudwatch_event_rule.ecs_events.name
  arn  = aws_cloudwatch_log_group.ecs_events.arn

  # EventBridge must already be allowed to write when the first event arrives.
  depends_on = [aws_cloudwatch_log_resource_policy.platform_logs]
}
