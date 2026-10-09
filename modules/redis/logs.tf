# Two logs that Redis can deliver to CloudWatch:
#   engine log - restarts, failovers and replication events.
#   slow log   - commands that took too long.
#
# The log group names use AWS's /aws/vendedlogs/ convention for logs that an AWS
# service delivers.

# The account and region in use, needed to write the policy's conditions below.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

resource "aws_cloudwatch_log_group" "engine_log" {
  name              = "/aws/vendedlogs/elasticache/${var.name}/engine-log"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/aws/vendedlogs/elasticache/${var.name}/slow-log"
  retention_in_days = var.log_retention_days
}

# Lets the CloudWatch Logs delivery service write to those two log groups, and
# only on behalf of this account.
resource "aws_cloudwatch_log_resource_policy" "redis_logs" {
  policy_name = "${var.name}-redis-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        "${aws_cloudwatch_log_group.engine_log.arn}:log-stream:*",
        "${aws_cloudwatch_log_group.slow_log.arn}:log-stream:*",
      ]
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:logs:${local.region}:${local.account_id}:*" }
      }
    }]
  })
}
