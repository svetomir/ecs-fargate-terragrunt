include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.7.3"
}

inputs = {
  name = include.root.locals.name_prefix
  cidr = "10.0.0.0/16"

  # Three zones, the same shape as prod. Subnets cost nothing, and more zones give
  # Fargate Spot more capacity to draw from.
  azs = [
    "${include.root.locals.aws_region}a",
    "${include.root.locals.aws_region}b",
    "${include.root.locals.aws_region}c",
  ]

  # Public subnets hold only the ALB and the NAT gateway, so they are small.
  public_subnets = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]

  # Private subnets hold the tasks. Every Fargate task takes one address.
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]

  # Data subnets hold Redis. Their route table has only the VPC's own local route,
  # so nothing in them can reach the internet or be reached from it.
  intra_subnets       = ["10.0.64.0/24", "10.0.65.0/24", "10.0.66.0/24"]
  intra_subnet_suffix = "data"

  # One NAT gateway shared by all three zones: cheaper, and an outage in its zone
  # only costs dev its outbound access.
  enable_nat_gateway = true
  single_nat_gateway = true
}
