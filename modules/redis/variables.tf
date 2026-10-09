variable "name" {
  description = "Prefix for resource names, for example ecs-fargate-dev."
  type        = string
}

# --- Where it runs ---

variable "vpc_id" {
  description = "VPC the Redis nodes and their security groups live in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the nodes may be placed in. Give one per zone for Multi-AZ."
  type        = list(string)
}

# --- The nodes ---

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "ElastiCache node type, for example cache.t4g.micro."
  type        = string
}

variable "num_cache_clusters" {
  description = "Number of nodes. 1 is a single node; 2 or more is a primary plus replicas with automatic failover."
  type        = number
}

# --- The AUTH token ---

variable "auth_token_version" {
  description = "Increase this number to generate a new AUTH token and give it to both the secret and Redis."
  type        = number
  default     = 1
}

variable "auth_secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps the AUTH token secret after it is deleted. 0 deletes it at once; otherwise 7 to 30."
  type        = number
}

# --- Backups and maintenance ---

variable "snapshot_retention_limit" {
  description = "Days to keep daily snapshots. 0 turns backups off."
  type        = number
}

variable "final_snapshot_identifier" {
  description = "Name of a snapshot to take when the replication group is deleted. Null skips it."
  type        = string
  default     = null
}

variable "snapshot_window" {
  description = "Daily time range, in UTC, for taking the snapshot, for example 01:00-02:00. Null lets AWS choose."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Weekly time range, in UTC, for maintenance, for example sun:03:00-sun:04:00. Null lets AWS choose."
  type        = string
  default     = null
}

variable "apply_immediately" {
  description = "True applies changes right away; false waits for the maintenance window."
  type        = bool
}

# --- Logs ---

variable "log_retention_days" {
  description = "Days CloudWatch keeps the Redis engine log and slow log."
  type        = number
}
