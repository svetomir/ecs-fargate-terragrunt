# The service is a stateless HTTP API whose requests are cheap, so load shows first
# in how many requests each task is handling. CPU is a second policy for the case
# where requests become expensive.
#
# With two target tracking policies, AWS adds tasks when either one asks for more
# and removes tasks only when both agree.
#
# There is no memory policy: for a service like this, memory hardly moves with
# the load, so a memory policy would have nothing to act on.

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"

  min_capacity = var.min_tasks
  max_capacity = var.max_tasks
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    # Requests per task per minute.
    target_value = var.requests_per_task_target

    # Add tasks quickly, remove them slowly, so a short dip does not cause flapping.
    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"

      # Tells CloudWatch which load balancer and target group to count requests for.
      resource_label = "${var.alb_arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
    }
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.cpu_target_percent

    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
