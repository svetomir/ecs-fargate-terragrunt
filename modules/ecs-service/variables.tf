variable "name" {
  description = "Name of the service and of everything created for it, for example ecs-fargate-dev-podinfo."
  type        = string
}

# --- Where it runs ---

variable "vpc_id" {
  description = "VPC the service runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets the tasks are placed in."
  type        = list(string)
}

variable "cluster_arn" {
  description = "ECS cluster the service runs in."
  type        = string
}

variable "cluster_name" {
  description = "Name of that cluster. Autoscaling identifies a service by cluster name and service name."
  type        = string
}

variable "capacity_provider" {
  description = "FARGATE for on-demand capacity or FARGATE_SPOT for cheaper capacity that can be interrupted."
  type        = string
}

# --- How traffic reaches it ---

variable "listener_arn" {
  description = "Load balancer listener the service adds its routing rule to."
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group of the load balancer. It is the only source allowed to reach the container port."
  type        = string
}

variable "listener_rule_priority" {
  description = "Position of this service's rule on the listener. Must be unique per listener; lower numbers are evaluated first."
  type        = number
}

variable "path_patterns" {
  description = "Paths the load balancer forwards to this service. Everything else gets the listener's default 404."
  type        = list(string)

  validation {
    condition     = length(var.path_patterns) >= 1 && length(var.path_patterns) <= 5
    error_message = "A listener rule takes between one and five path patterns."
  }
}

# --- The container ---

variable "image" {
  description = "Container image, with a fixed tag."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
}

variable "cpu" {
  description = "CPU units for the task. 1024 is one vCPU."
  type        = number
}

variable "memory" {
  description = "Memory for the task, in MiB."
  type        = number
}

variable "environment" {
  description = "Plain configuration, as environment variable name to value. Visible in the task definition."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret configuration, as environment variable name to Secrets Manager secret ARN. ECS fetches the values when a task starts."
  type        = map(string)
  default     = {}
}

# --- Health ---

variable "readiness_path" {
  description = "Path the load balancer polls to decide whether a task should receive traffic."
  type        = string
}

variable "liveness_command" {
  description = "Command ECS runs inside the container to decide whether the task should be replaced. The tool it uses must exist in the image."
  type        = list(string)
}

# --- Redis ---

variable "redis" {
  description = "The Redis this service needs, or null for a service that does not use Redis. When set, a startup check must reach Redis before the application starts, and the tasks join its client security group."
  type = object({
    host                     = string # Address of the primary endpoint.
    port                     = number # Port Redis listens on.
    client_security_group_id = string # Security group that is allowed to reach Redis.
    auth_secret_arn          = string # Secrets Manager secret holding the AUTH token.
  })
  default = null
}

# --- Scaling ---

variable "min_tasks" {
  description = "Fewest tasks autoscaling may run. The service also starts with this many."
  type        = number
}

variable "max_tasks" {
  description = "Most tasks autoscaling may run."
  type        = number
}

variable "requests_per_task_target" {
  description = "Requests per task per minute that autoscaling aims for. Set it below what one task can serve comfortably."
  type        = number
}

variable "cpu_target_percent" {
  description = "Average CPU utilisation, in percent, that autoscaling aims to stay under."
  type        = number
  default     = 60
}

variable "alb_arn_suffix" {
  description = "Load balancer identifier used in CloudWatch metrics. Needed to read this service's request count."
  type        = string
}

# --- Logs ---

variable "log_retention_days" {
  description = "Days CloudWatch keeps the container logs."
  type        = number
}
