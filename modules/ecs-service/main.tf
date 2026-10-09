data "aws_region" "current" {}

locals {
  # The startup check: connect to Redis over TLS, send PING, and succeed only if
  # the reply is PONG.
  #
  # redis-cli reads the token from REDISCLI_AUTH. `timeout` stops it hanging on a
  # blocked connection. The reply is printed, so a failure is visible in the logs.
  # The last line decides the result: redis-cli exits 0 even when Redis refuses
  # the token, so the script compares the reply instead of trusting the exit code.
  redis_check_script = <<-EOT
    reply=$(timeout 10 redis-cli --tls -h ${var.redis_host} -p ${var.redis_port} ping 2>&1)
    echo "Redis replied: $reply"
    [ "$reply" = PONG ]
  EOT

  # Takes away every Linux capability a container gets by default. `add = []`
  # adds nothing. It is written out because AWS stores it that way; without it
  # Terraform sees a difference on every plan and replaces the task definition.
  no_capabilities = { capabilities = { add = [], drop = ["ALL"] } }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # The container list is in ECS's own JSON format, which is why the keys inside
  # it are camelCase, unlike the rest of this file.
  container_definitions = jsonencode([
    # Runs first and exits. The application only starts if this check succeeds, so
    # a task that cannot reach or log in to Redis never takes traffic.
    {
      name      = "redis-check"
      image     = var.redis_check_image
      essential = false

      # Least privilege inside the container: not root, an image it cannot write
      # to, and none of the Linux capabilities containers get by default.
      user                   = "redis"
      readonlyRootFilesystem = true
      linuxParameters        = local.no_capabilities

      command = ["sh", "-c", local.redis_check_script]

      secrets = [{
        name      = "REDISCLI_AUTH"
        valueFrom = var.redis_auth_secret_arn
      }]

      # Non-blocking: if CloudWatch Logs is slow or unreachable, log lines wait in
      # a 25 MB buffer and the container keeps running. If the buffer fills, lines
      # are dropped, which is better than a container stalled on writing a log line.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "redis-check"
          mode                  = "non-blocking"
          max-buffer-size       = "25m"
        }
      }
    },
    {
      name      = "app"
      image     = var.image
      essential = true

      # The image already runs as a non-root user. It also cannot write to its own
      # filesystem and has no Linux capabilities.
      readonlyRootFilesystem = true
      linuxParameters        = local.no_capabilities

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]

      # Plain values are stored in the task definition. Secrets are stored as ARNs
      # only; ECS fetches the values with the execution role when the task starts.
      environment = [for name, value in var.environment : { name = name, value = value }]
      secrets     = [for name, arn in var.secrets : { name = name, valueFrom = arn }]

      dependsOn = [{
        containerName = "redis-check"
        condition     = "SUCCESS"
      }]

      # ECS runs this command inside the container every 30 seconds and allows it
      # 5 seconds. Three failures in a row mark the task unhealthy, and ECS
      # replaces it. Failures in the first 10 seconds after start are not counted.
      healthCheck = {
        command     = var.liveness_command
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      # The same non-blocking logging as the check above.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
          mode                  = "non-blocking"
          max-buffer-size       = "25m"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn

  # Only the starting count. Autoscaling changes it afterwards, and the lifecycle
  # block below stops Terraform from putting it back on the next apply.
  desired_count = var.min_tasks

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id, var.redis_client_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # Tasks inherit the service's tags, so their cost can be attributed to the
  # project and environment. ECS also adds its own tags naming the cluster and service.
  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true

  # Keeps tasks evenly spread across zones. ECS only spreads them when it places
  # them; after a zone problem or a scale-in this moves tasks to even them out.
  availability_zone_rebalancing = "ENABLED"

  # Time a new task gets to start before load balancer health checks count against it.
  health_check_grace_period_seconds = 60

  # Rolling deploy: start new tasks before stopping old ones, never dropping below
  # the desired count.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If new tasks keep failing, including a failed Redis check, stop the deployment
  # and return to the last working version.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # `apply` waits until the new tasks are running and healthy, and fails if they
  # are not, instead of reporting success as soon as ECS accepts the change.
  wait_for_steady_state = true

  # Terraform would otherwise create the service as soon as the target group and
  # roles exist. The target group must be attached to the listener first, and the
  # first task needs the execution role's permissions to start.
  depends_on = [
    aws_lb_listener_rule.this,
    aws_iam_role_policy.execution_logs,
    aws_iam_role_policy.execution_secrets,
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
