# Checks the module's optional inputs and the inputs it refuses: Redis, a private
# image, further security groups, the target group's name, and the validations.
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

# The inputs every service needs. Each run changes only what it names.
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

  assert {
    condition     = length(aws_iam_role_policy.execution_pull) == 0
    error_message = "For a public image, the policy for pulling images should not exist."
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

run "private_image" {
  variables {
    ecr_repository_arns = ["arn:aws:ecr:us-east-1:000000000000:repository/app"]
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.execution_pull[0].policy).Statement[1].Resource == ["arn:aws:ecr:us-east-1:000000000000:repository/app"]
    error_message = "The execution role should be able to pull from the repository it was given and no other."
  }
}

run "further_security_groups" {
  variables {
    additional_security_group_ids = ["sg-00000000000000003"]
  }

  assert {
    condition     = length(aws_ecs_service.this.network_configuration[0].security_groups) == 2
    error_message = "The tasks should carry the service's own group and the one passed in."
  }

  assert {
    condition     = contains(aws_ecs_service.this.network_configuration[0].security_groups, "sg-00000000000000003")
    error_message = "The group passed in should be attached to the tasks."
  }
}

# A changed port has to give the target group a new name. See network.tf.
run "target_group_name_follows_the_port" {
  variables {
    container_port = 9090
  }

  assert {
    condition     = aws_lb_target_group.this.name == "test-service-9090"
    error_message = "The target group's name should end in the container port."
  }
}

# The longest name the module accepts, with the longest port, is a target group
# name of exactly 32 characters. The provider checks that length itself.
run "accepts_the_longest_name" {
  command = plan

  variables {
    name           = "a-name-of-26-characters-xx"
    container_port = 65535
  }

  assert {
    condition     = length(aws_lb_target_group.this.name) == 32
    error_message = "A 26-character name and a five-digit port should give a 32-character target group name."
  }
}

run "rejects_a_longer_name" {
  command = plan

  variables {
    name = "a-name-of-27-characters-xxx"
  }

  expect_failures = [var.name]
}

run "rejects_an_unknown_capacity_provider" {
  command = plan

  variables {
    capacity_provider = "EC2"
  }

  expect_failures = [var.capacity_provider]
}

run "rejects_max_tasks_below_min_tasks" {
  command = plan

  variables {
    min_tasks = 3
    max_tasks = 2
  }

  expect_failures = [var.max_tasks]
}
