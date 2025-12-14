# Development Environment
# Local development environment using Talos on Docker/QEMU

terraform {
  required_version = ">= 1.5.0"

  # Backend configuration for state storage
  # For dev, we can use local backend or S3
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Provider configurations will be dynamically selected based on provider_type variable
variable "provider_type" {
  type        = string
  description = "Cloud provider for dev cluster: aws, gcp, digitalocean"
  default     = "aws"
}

variable "region" {
  type        = string
  description = "InferaDB region (nyc1 or sfo1)"
  default     = "nyc1"
}

# Load region-specific variables
module "region_config" {
  source = "../../regions/${var.region}"
}

# Development cluster configuration
module "dev_cluster" {
  source = "../../modules/talos-cluster"

  cluster_name    = "inferadb-dev"
  provider_type   = var.provider_type
  region          = var.region
  provider_region = module.region_config.region_mappings[var.provider_type]
  environment     = "dev"

  # Minimal resources for development
  control_plane_count = 1
  worker_count        = 2
  worker_machine_type = "small"

  # Enable spot instances for cost savings in dev
  use_spot_instances = true
  spot_max_price     = "" # Use on-demand price cap

  # Talos and Kubernetes versions
  talos_version      = "v1.8.0"
  kubernetes_version = "1.30.0"

  # Network configuration (will be provided by provider-specific modules)
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  tags = {
    Purpose    = "development"
    CostCenter = "engineering"
    Terraform  = "true"
  }
}

# Variables for networking (provider-specific)
variable "vpc_id" {
  type        = string
  description = "VPC ID for the cluster"
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the cluster"
  default     = []
}

# Outputs
output "kubeconfig" {
  description = "Kubeconfig for the development cluster"
  value       = module.dev_cluster.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Talosconfig for the development cluster"
  value       = module.dev_cluster.talosconfig
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.dev_cluster.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = module.dev_cluster.cluster_name
}
