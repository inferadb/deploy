# SFO1 Region Configuration
# Maps InferaDB region 'sfo1' to provider-specific regions

locals {
  # Region mappings for SFO1
  region_mappings = {
    aws          = "us-west-1"
    gcp          = "us-west1"
    digitalocean = "sfo3" # DigitalOcean doesn't have sfo1, using sfo3
  }

  # Machine type mappings across providers
  # AWS: Using Graviton (t4g) for ~20% cost savings over x86 (t3)
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

  # Region-specific configuration
  region_config = {
    name         = "sfo1"
    display_name = "San Francisco 1"
    primary      = false # Secondary region for DR/multi-region
  }
}
