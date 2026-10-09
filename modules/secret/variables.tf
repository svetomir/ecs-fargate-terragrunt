variable "name" {
  description = "Name of the secret, for example ecs-fargate-dev/podinfo/jwt-secret."
  type        = string
}

variable "description" {
  description = "What the secret is for."
  type        = string
}

variable "recovery_window_in_days" {
  description = "Days Secrets Manager keeps the secret after it is deleted. 0 deletes it at once; otherwise 7 to 30."
  type        = number
}

variable "value_version" {
  description = "Increase this number to generate and store a new value."
  type        = number
  default     = 1
}
