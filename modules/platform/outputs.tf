output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster. Service autoscaling identifies a service by cluster name."
  value       = aws_ecs_cluster.this.name
}

output "listener_arn" {
  description = "Listener that services attach their routing rules to."
  value       = aws_lb_listener.http.arn
}

output "alb_security_group_id" {
  description = "Security group of the load balancer. Services allow their container port from it."
  value       = aws_security_group.alb.id
}

output "alb_arn_suffix" {
  description = "Load balancer identifier used in CloudWatch metrics, needed for request-based scaling."
  value       = aws_lb.this.arn_suffix
}

output "access_logs_log_group" {
  description = "CloudWatch log group holding the load balancer's access logs."
  value       = aws_cloudwatch_log_group.access_logs.name
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}
