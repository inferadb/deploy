# Production Environment
# Multi-region production deployment with high availability

terraform {
  required_version = ">= 1.5.0"

  # Backend configuration for remote state storage
  # Production uses S3/GCS with state locking and versioning
  backend "s3" {
    bucket         = "inferadb-terraform-state-production"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "inferadb-terraform-locks"
    # Enable versioning and lifecycle policies on the bucket
  }
}

# Provider configurations
variable "provider_type" {
  type        = string
  description = "Cloud provider for production cluster: aws, gcp, digitalocean"
  default     = "aws"
}

# Production NYC1 cluster (Primary)
module "production_nyc1" {
  source = "../../modules/talos-cluster"

  cluster_name    = "inferadb-prod-nyc1"
  provider_type   = var.provider_type
  region          = "nyc1"
  provider_region = lookup(module.nyc1_config.region_mappings, var.provider_type, "us-east-1")
  environment     = "production"

  # Production configuration - high availability
  control_plane_count = 3
  worker_count        = 5
  worker_machine_type = "large"

  # DO NOT use spot instances for stateful workloads in production
  # Spot instances are configured via Kubernetes node pools for stateless apps
  use_spot_instances = false

  # Talos and Kubernetes versions
  talos_version      = "v1.8.0"
  kubernetes_version = "1.30.0"

  # Network configuration
  vpc_id     = var.vpc_id_nyc1
  subnet_ids = var.subnet_ids_nyc1

  tags = {
    Purpose     = "production"
    Environment = "production"
    CostCenter  = "operations"
    Terraform   = "true"
    Region      = "nyc1"
    Critical    = "true"
  }
}

# Production SFO1 cluster (DR/Secondary)
module "production_sfo1" {
  source = "../../modules/talos-cluster"

  cluster_name    = "inferadb-prod-sfo1"
  provider_type   = var.provider_type
  region          = "sfo1"
  provider_region = lookup(module.sfo1_config.region_mappings, var.provider_type, "us-west-1")
  environment     = "production"

  # Production configuration - high availability
  control_plane_count = 3
  worker_count        = 5
  worker_machine_type = "large"

  # DO NOT use spot instances for stateful workloads in production
  use_spot_instances = false

  # Talos and Kubernetes versions (match NYC1)
  talos_version      = "v1.8.0"
  kubernetes_version = "1.30.0"

  # Network configuration
  vpc_id     = var.vpc_id_sfo1
  subnet_ids = var.subnet_ids_sfo1

  tags = {
    Purpose     = "production"
    Environment = "production"
    CostCenter  = "operations"
    Terraform   = "true"
    Region      = "sfo1"
    Critical    = "true"
  }
}

# Region configurations
module "nyc1_config" {
  source = "../../regions/nyc1"
}

module "sfo1_config" {
  source = "../../regions/sfo1"
}

# Variables
variable "vpc_id_nyc1" {
  type        = string
  description = "VPC ID for NYC1 cluster"
}

variable "subnet_ids_nyc1" {
  type        = list(string)
  description = "Subnet IDs for NYC1 cluster (must span multiple AZs)"
}

variable "vpc_id_sfo1" {
  type        = string
  description = "VPC ID for SFO1 cluster"
}

variable "subnet_ids_sfo1" {
  type        = list(string)
  description = "Subnet IDs for SFO1 cluster (must span multiple AZs)"
}

# Outputs
output "nyc1_kubeconfig" {
  description = "Kubeconfig for production NYC1 cluster"
  value       = module.production_nyc1.kubeconfig
  sensitive   = true
}

output "nyc1_talosconfig" {
  description = "Talosconfig for production NYC1 cluster"
  value       = module.production_nyc1.talosconfig
  sensitive   = true
}

output "nyc1_cluster_endpoint" {
  description = "NYC1 cluster endpoint"
  value       = module.production_nyc1.cluster_endpoint
}

output "nyc1_control_plane_ips" {
  description = "NYC1 control plane IPs"
  value       = module.production_nyc1.control_plane_ips
}

output "sfo1_kubeconfig" {
  description = "Kubeconfig for production SFO1 cluster"
  value       = module.production_sfo1.kubeconfig
  sensitive   = true
}

output "sfo1_talosconfig" {
  description = "Talosconfig for production SFO1 cluster"
  value       = module.production_sfo1.talosconfig
  sensitive   = true
}

output "sfo1_cluster_endpoint" {
  description = "SFO1 cluster endpoint"
  value       = module.production_sfo1.cluster_endpoint
}

output "sfo1_control_plane_ips" {
  description = "SFO1 control plane IPs"
  value       = module.production_sfo1.control_plane_ips
}

# Production cluster metadata
output "clusters" {
  description = "Production cluster information"
  value = {
    nyc1 = {
      name     = module.production_nyc1.cluster_name
      endpoint = module.production_nyc1.cluster_endpoint
      region   = "nyc1"
      primary  = true
    }
    sfo1 = {
      name     = module.production_sfo1.cluster_name
      endpoint = module.production_sfo1.cluster_endpoint
      region   = "sfo1"
      primary  = false
    }
  }
}
