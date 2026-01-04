# TFLint configuration for InferaDB deploy repository
# See: https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md

config {
  format     = "compact"
  module     = true
  force      = false
  plugin_dir = "~/.tflint.d/plugins"
}

# Terraform plugin - general best practices
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS plugin - AWS-specific rules
plugin "aws" {
  enabled = true
  version = "0.34.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# GCP plugin - Google Cloud-specific rules
plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"

  custom_formats = {
    # Allow hyphens in resource names (common for cloud resources)
    resource_name = {
      description = "Resource names can use snake_case or kebab-case"
      regex       = "^[a-z][a-z0-9_-]*$"
    }
  }
}

# Require variable documentation
rule "terraform_documented_variables" {
  enabled = true
}

# Require output documentation
rule "terraform_documented_outputs" {
  enabled = true
}

# Require type declarations for variables
rule "terraform_typed_variables" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Deprecated interpolation syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Deprecated index usage
rule "terraform_deprecated_index" {
  enabled = true
}

# Comment syntax
rule "terraform_comment_syntax" {
  enabled = true
}

# Unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Required version constraint
rule "terraform_required_version" {
  enabled = true
}

# Required providers
rule "terraform_required_providers" {
  enabled = true
}

# Workspace remote
rule "terraform_workspace_remote" {
  enabled = true
}

# Empty list equality checks
rule "terraform_empty_list_equality" {
  enabled = true
}

# Module version - disabled (we use local modules)
rule "terraform_module_version" {
  enabled = false
}

# AWS-specific rules to disable (we use multi-cloud abstractions)
rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_instance_previous_type" {
  enabled = true
}

# GCP-specific rules
rule "google_compute_instance_invalid_machine_type" {
  enabled = true
}
