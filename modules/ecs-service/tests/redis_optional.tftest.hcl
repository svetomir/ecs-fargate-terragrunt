# Checks that Redis really is optional in this module.
#
# Run it with `terraform test` in modules/ecs-service. The AWS provider is mocked,
# so it needs no credentials and creates nothing.

# A mocked provider invents a random string for every value AWS would return.
# The provider still checks that an ARN looks like one, so those get a fixed value.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/mock"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:000000000000:targetgroup/mock/0000000000000000"
      arn_suffix = "targetgroup/mock/0000000000000000"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:000000000000:task-definition/mock:1"
    }
  }
}

# The inputs every service needs. Neither run changes them.
variables {
  name                     = "test-service"
  vpc_id                   = "vpc-00000000000000000"
  subnet_ids               = ["subnet-00000000000000001", "subnet-00000000000000002"]
  cluster_arn              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  cluster_name             = "test"
  capacity_provider        = "FARGATE"
  listener_arn             = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/test/0000000000000000/0000000000000000"
  alb_security_group_id    = "sg-00000000000000001"
  alb_arn_suffix           = "app/test/0000000000000000"
  listener_rule_priority   = 100
  path_patterns            = ["/"]
  image                    = "example/app:1.0.0"
  container_port           = 8080
  cpu                      = 256
  memory                   = 512
  readiness_path           = "/"
  liveness_command         = ["CMD-SHELL", "true"]
  min_tasks                = 1
  max_tasks                = 2
  requests_per_task_target = 100
  log_retention_days       = 7
}

run "without_redis" {
  assert {
    condition     = [for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name] == ["app"]
    error_message = "A service without Redis should have the app container and nothing else."
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].dependsOn) == 0
    error_message = "Without a Redis check, the app should not wait for one."
  }

  assert {
    condition     = length(aws_ecs_service.this.network_configuration[0].security_groups) == 1
    error_message = "A service without Redis should carry only its own security group."
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_secrets) == 0
    error_message = "With no secrets at all, the policy for reading secrets should not exist."
  }
}

run "with_redis" {
  variables {
    redis = {
      host                     = "redis.example.internal"
      port                     = 6379
      client_security_group_id = "sg-00000000000000002"
      auth_secret_arn          = "arn:aws:secretsmanager:us-east-1:000000000000:secret:redis-token"
    }
  }

  assert {
    condition     = [for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name] == ["redis-check", "app"]
    error_message = "A service with Redis should run the check container before the app."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].dependsOn == [{ condition = "SUCCESS", containerName = "redis-check" }]
    error_message = "The app should start only after the Redis check succeeds."
  }

  assert {
    condition     = strcontains(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].command[2], "-h redis.example.internal -p 6379")
    error_message = "The check should target the host and port it was given."
  }

  assert {
    condition     = length(aws_ecs_service.this.network_configuration[0].security_groups) == 2
    error_message = "A service with Redis should also carry the Redis client security group."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.execution_secrets[0].policy).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:000000000000:secret:redis-token"]
    error_message = "The execution role should be able to read the Redis token and nothing more."
  }
}
