# Two groups, so that everything about who may reach Redis lives in this module:
#   redis  - on the nodes. Accepts the Redis port from the client group and nothing else.
#   client - attached by anything that needs Redis. Being a member is the permission.
#
# Rules are separate resources because the two groups refer to each other.

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "ElastiCache Redis nodes"
  vpc_id      = var.vpc_id
}

resource "aws_security_group" "client" {
  name        = "${var.name}-redis-client"
  description = "Attach to workloads that need to reach Redis"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_client" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.client.id
  description                  = "Redis from members of the client group"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_egress_rule" "client_to_redis" {
  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.redis.id
  description                  = "Redis on the nodes"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}
