# Action logs: a record of every operation ECS performs in this cluster on the
# account's behalf. They are delivered through CloudWatch Logs, the same way as
# the load balancer's access logs.

resource "aws_cloudwatch_log_group" "action_logs" {
  name              = "/aws/vendedlogs/ecs/${var.name}/action-logs"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_delivery_source" "action_logs" {
  name         = "${var.name}-ecs-actions"
  log_type     = "ACTION_LOGS"
  resource_arn = aws_ecs_cluster.this.arn
}

resource "aws_cloudwatch_log_delivery_destination" "action_logs" {
  name          = "${var.name}-ecs-actions"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.action_logs.arn
  }
}

resource "aws_cloudwatch_log_delivery" "action_logs" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.action_logs.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.action_logs.arn

  # The delivery service must already be allowed to write when delivery starts.
  depends_on = [aws_cloudwatch_log_resource_policy.platform_logs]
}
