# Who may write into this module's log groups. It is one policy for all of them,
# because an account can have only ten of these policies per region.

resource "aws_cloudwatch_log_resource_policy" "platform_logs" {
  policy_name = "${var.name}-platform-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # The CloudWatch Logs delivery service, for the logs AWS services deliver,
      # and only on behalf of this account.
      {
        Sid       = "ServiceDeliveredLogs"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "${aws_cloudwatch_log_group.access_logs.arn}:log-stream:*",
          "${aws_cloudwatch_log_group.action_logs.arn}:log-stream:*",
        ]
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:logs:${local.region}:${local.account_id}:*" }
        }
      },
      # EventBridge, for the ECS events it forwards.
      {
        Sid       = "EcsEvents"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.ecs_events.arn}:*"
      },
    ]
  })
}
