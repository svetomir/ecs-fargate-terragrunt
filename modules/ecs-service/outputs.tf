output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_role_name" {
  description = "Role the application runs as. Attach policies here if it ever needs AWS access."
  value       = aws_iam_role.task.name
}

output "log_group_name" {
  description = "CloudWatch log group holding the container logs."
  value       = aws_cloudwatch_log_group.this.name
}
