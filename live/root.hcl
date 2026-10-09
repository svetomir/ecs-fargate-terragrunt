# Shared by every unit under live/. Each unit pulls this in with an `include` block.
# `expose = true` on that block lets the unit read the locals below, for example
# `include.root.locals.name_prefix`.

locals {
  project    = "ecs-fargate"
  aws_region = "us-east-1"

  # The three zones every environment uses, by zone ID. A zone name such as
  # us-east-1a is an alias AWS assigns per account, so it can mean a different
  # physical zone for each reader. A zone ID is the same zone for everyone.
  # use1-az3 is left out because AWS has listed it as not offering Fargate.
  availability_zones = ["use1-az1", "use1-az2", "use1-az4"]

  # Read from live/<env>/env.hcl, found by walking up from the unit that includes this file.
  environment = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.environment

  # Prefix for resource names, so dev and prod can share one account without colliding.
  name_prefix = "${local.project}-${local.environment}"

  # Looked up from the caller's credentials. It makes the state bucket name unique per
  # account, so nobody has to edit this file to plan in their own account.
  account_id = get_aws_account_id()

  # Where the state is kept. By default a bucket of this repo's own, named after the
  # account and region. To use a bucket you already have, set STATE_BUCKET in your
  # shell, and STATE_BUCKET_REGION too if that bucket is in another region.
  state_bucket        = get_env("STATE_BUCKET", "tfstate-${local.account_id}-${local.aws_region}")
  state_bucket_region = get_env("STATE_BUCKET_REGION", local.aws_region)
}

# Fail early with a clear message on tool versions this repo was not written for.
# 1.11 is the first release with S3 native state locking and write-only arguments.
terraform_version_constraint  = ">= 1.11"
terragrunt_version_constraint = ">= 1.0"

# State: one S3 bucket, one key per unit. Every key starts with the project name,
# for example ecs-fargate/dev/network/terraform.tfstate, so this repo's state cannot
# collide with another project's in a shared bucket.
# `use_lockfile` locks through S3 itself, so there is no DynamoDB table.
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_bucket
    key          = "${local.project}/${path_relative_to_include()}/terraform.tfstate"
    region       = local.state_bucket_region
    encrypt      = true
    use_lockfile = true
  }
}

# Modules stay free of provider configuration; every unit gets this one.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Project     = "${local.project}"
          Environment = "${local.environment}"
          ManagedBy   = "terragrunt"
        }
      }
    }
  EOF
}
