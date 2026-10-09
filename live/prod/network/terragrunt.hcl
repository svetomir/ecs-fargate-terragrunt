include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.7.3"
}

inputs = {
  name = include.root.locals.name_prefix

  # Does not overlap dev (10.0.0.0/16), so the two could be connected later.
  cidr = "10.1.0.0/16"

  # Three zones: losing one takes out a third of capacity instead of half.
  azs = [
    "${include.root.locals.aws_region}a",
    "${include.root.locals.aws_region}b",
    "${include.root.locals.aws_region}c",
  ]

  # Public subnets hold only the ALB and the NAT gateways, so they are small.
  public_subnets = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]

  # Private subnets hold the tasks. Every Fargate task takes one address.
  private_subnets = ["10.1.16.0/20", "10.1.32.0/20", "10.1.48.0/20"]

  # Data subnets hold Redis. Their route table has only the VPC's own local route,
  # so nothing in them can reach the internet or be reached from it.
  intra_subnets       = ["10.1.64.0/24", "10.1.65.0/24", "10.1.66.0/24"]
  intra_subnet_suffix = "data"

  # One NAT gateway per zone, each private subnet routing to the one in its own zone,
  # so a zone outage does not cut outbound access for the other two.
  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
}
