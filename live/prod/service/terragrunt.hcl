include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules//ecs-service"
}

# Every dependency has placeholder outputs so this unit can be planned before the
# others have been applied. They are only allowed for the commands listed; apply
# needs the real outputs.

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "platform" {
  config_path = "../platform"

  mock_outputs = {
    cluster_arn           = "arn:aws:ecs:us-east-1:000000000000:cluster/mock"
    cluster_name          = "mock"
    listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/mock/0000000000000000/0000000000000000"
    alb_security_group_id = "sg-00000000000000001"
    alb_arn_suffix        = "app/mock/0000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "redis" {
  config_path = "../redis"

  mock_outputs = {
    primary_endpoint_address = "mock-redis.invalid"
    port                     = 6379
    client_security_group_id = "sg-00000000000000002"
    auth_token_secret_arn    = "arn:aws:secretsmanager:us-east-1:000000000000:secret:mock-redis-auth-000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "secret" {
  config_path = "../secret"

  mock_outputs = {
    arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:mock-000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name = "${include.root.locals.name_prefix}-podinfo"

  # Where it runs.
  vpc_id       = dependency.network.outputs.vpc_id
  subnet_ids   = dependency.network.outputs.private_subnets
  cluster_arn  = dependency.platform.outputs.cluster_arn
  cluster_name = dependency.platform.outputs.cluster_name

  # How traffic reaches it. Only these paths are forwarded; podinfo's /env, which
  # prints its environment, and /panic, which kills the process, are not among them.
  listener_arn           = dependency.platform.outputs.listener_arn
  alb_security_group_id  = dependency.platform.outputs.alb_security_group_id
  listener_rule_priority = 100
  path_patterns          = ["/", "/version", "/api/*", "/token*"]

  # The container.
  image          = "ghcr.io/stefanprodan/podinfo:6.15.0"
  container_port = 9898

  # Readiness is checked by the load balancer, liveness inside the container.
  readiness_path   = "/readyz"
  liveness_command = ["CMD-SHELL", "curl -fsS http://localhost:9898/healthz || exit 1"]

  environment = {
    PODINFO_UI_MESSAGE = "podinfo in ${include.root.locals.environment}"
  }

  # podinfo signs the tokens it issues with this key.
  secrets = {
    PODINFO_JWT_SECRET = dependency.secret.outputs.arn
  }

  # Redis: where it is, the security group that may reach it, and the secret
  # holding its AUTH token.
  redis_host                     = dependency.redis.outputs.primary_endpoint_address
  redis_port                     = dependency.redis.outputs.port
  redis_client_security_group_id = dependency.redis.outputs.client_security_group_id
  redis_auth_secret_arn          = dependency.redis.outputs.auth_token_secret_arn

  # Larger tasks on on-demand capacity, which cannot be reclaimed.
  cpu               = 512
  memory            = 1024
  capacity_provider = "FARGATE"

  # Scaling. Never fewer than three tasks, so there is one per zone and losing a
  # zone leaves two. The request target is a placeholder until the service is
  # load-tested: it should sit at about two thirds of what one task serves well.
  min_tasks                = 3
  max_tasks                = 12
  requests_per_task_target = 3000

  # Which load balancer's metrics the request count is read from.
  alb_arn_suffix = dependency.platform.outputs.alb_arn_suffix

  log_retention_days = 90
}
