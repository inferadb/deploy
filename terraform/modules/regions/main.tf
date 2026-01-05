# Consolidated Region Configuration Module
# Provides region-specific mappings for all InferaDB regions
#
# Usage:
#   module "regions" {
#     source = "../../modules/regions"
#   }
#   # Access: module.regions.all["nyc1"].region_mappings.aws

terraform {
  required_version = ">= 1.5.0"
}

locals {
  # NYC1 Region Configuration
  nyc1 = {
    region_mappings = {
      aws          = "us-east-1"
      gcp          = "us-east4"
      digitalocean = "nyc1"
    }

    machine_type_mappings = {
      small = {
        aws          = "t4g.medium"
        gcp          = "e2-medium"
        digitalocean = "s-2vcpu-4gb"
      }
      medium = {
        aws          = "t4g.xlarge"
        gcp          = "e2-standard-4"
        digitalocean = "s-4vcpu-8gb"
      }
      large = {
        aws          = "t4g.2xlarge"
        gcp          = "e2-standard-8"
        digitalocean = "s-8vcpu-16gb"
      }
    }

    region_config = {
      name         = "nyc1"
      display_name = "New York City 1"
      primary      = true
    }
  }

  # SFO1 Region Configuration
  sfo1 = {
    region_mappings = {
      aws          = "us-west-1"
      gcp          = "us-west1"
      digitalocean = "sfo3" # DigitalOcean doesn't have sfo1, using sfo3
    }

    machine_type_mappings = {
      small = {
        aws          = "t4g.medium"
        gcp          = "e2-medium"
        digitalocean = "s-2vcpu-4gb"
      }
      medium = {
        aws          = "t4g.xlarge"
        gcp          = "e2-standard-4"
        digitalocean = "s-4vcpu-8gb"
      }
      large = {
        aws          = "t4g.2xlarge"
        gcp          = "e2-standard-8"
        digitalocean = "s-8vcpu-16gb"
      }
    }

    region_config = {
      name         = "sfo1"
      display_name = "San Francisco 1"
      primary      = false
    }
  }

  # All regions consolidated
  all_regions = {
    nyc1 = local.nyc1
    sfo1 = local.sfo1
  }
}
