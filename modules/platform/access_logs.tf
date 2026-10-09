# Access logs for the load balancer: one record per request, with the client
# address, the path, the status and the timings.
#
# They are the only record of requests the listener rejects. Those never reach a
# task, so they never appear in the container logs.
#
# They are delivered through CloudWatch Logs, which is the mechanism AWS now
# recommends. Switching logs on as a load balancer attribute, with an S3 bucket,
# is the older way that AWS labels "legacy".

# The /aws/vendedlogs/ prefix is AWS's naming convention for log groups that an
# AWS service delivers into.
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/vendedlogs/alb/${var.name}"
  retention_in_days = var.log_retention_days
}

# A delivery has three parts. The source: what produces the logs.
resource "aws_cloudwatch_log_delivery_source" "access_logs" {
  name         = "${var.name}-alb-access"
  log_type     = "ALB_ACCESS_LOGS"
  resource_arn = aws_lb.this.arn
}

# The destination: where they go.
resource "aws_cloudwatch_log_delivery_destination" "access_logs" {
  name          = "${var.name}-alb-access"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.access_logs.arn
  }
}

# And the delivery itself, which connects the two.
resource "aws_cloudwatch_log_delivery" "access_logs" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.access_logs.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.access_logs.arn

  # The delivery service must already be allowed to write when delivery starts.
  depends_on = [aws_cloudwatch_log_resource_policy.platform_logs]
}
