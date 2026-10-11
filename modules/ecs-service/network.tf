# How traffic reaches the tasks. The security group says what a task may receive
# and send. The target group and listener rule say which requests the load
# balancer forwards to it.

# The tasks' own security group. These rules, and those of any other group
# attached in main.tf, are everything a task may receive or send.
resource "aws_security_group" "service" {
  name        = var.name
  description = "Tasks of ${var.name}"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = var.alb_security_group_id
  description                  = "Container port from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Pulling images, reading the secret and shipping logs all use HTTPS.
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS for image pulls, Secrets Manager and CloudWatch Logs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# The load balancer's list of this service's tasks.
#
# AWS cannot change a target group's port in place, so a new port means a new
# target group. With one fixed name that could not work: the old group would have
# to be deleted first to free the name, and AWS refuses to delete a group that a
# listener rule still forwards to. So the port is part of the name, and the
# lifecycle block at the end creates the new group before the old one is deleted.
# In between, the listener rule and the service move over to the new group.
resource "aws_lb_target_group" "this" {
  name     = "${var.name}-${var.container_port}"
  vpc_id   = var.vpc_id
  port     = var.container_port
  protocol = "HTTP"

  # Fargate tasks have their own network interface, so they register by IP address.
  target_type = "ip"

  # Seconds a task keeps finishing in-flight requests after it is taken out of rotation.
  deregistration_delay = 30

  # The load balancer asks every task for this path every 15 seconds and allows
  # it 5 seconds. Two passes in a row put a task into rotation. Three failures in
  # a row take it out, and ECS then replaces the task.
  health_check {
    path                = var.readiness_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The service's claim on the shared listener: only these paths are forwarded to it.
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  condition {
    path_pattern {
      values = var.path_patterns
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
