include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules//secret"
}

inputs = {
  name        = "${include.root.locals.name_prefix}/podinfo/jwt-secret"
  description = "Signing key for the tokens podinfo issues"

  # Deleted at once on destroy, so dev can be torn down and recreated under the same name.
  recovery_window_in_days = 0
}
