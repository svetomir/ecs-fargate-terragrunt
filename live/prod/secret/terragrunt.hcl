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

  # Kept for 30 days after a delete, so a mistaken destroy can be undone.
  recovery_window_in_days = 30
}
