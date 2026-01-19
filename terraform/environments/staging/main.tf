# Staging Environment
# Multi-region staging environment for pre-production testing

terraform {
  required_version = ">= 1.5.0"

  # Backend configuration for remote state storage
  # In production, use S3/GCS with state locking
  backend "s3" {
    bucket         = "inferadb-terraform-state-staging"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "inferadb-terraform-locks"
  }
}

# Provider configurations
variable "provider_type" {
  type        = string
  description = "Cloud provider for staging cluster: aws, gcp, digitalocean"
  default     = "aws"
}

variable "region" {
  type        = string
  description = "InferaDB region (nyc1 or sfo1)"
  default     = "nyc1"
}

variable "cluster_endpoint_hostname_nyc1" {
  type        = string
  description = "Pre-allocated hostname for NYC1 cluster API endpoint"
  default     = "api.staging-nyc1.inferadb.io"
}

variable "cluster_endpoint_hostname_sfo1" {
  type        = string
  description = "Pre-allocated hostname for SFO1 cluster API endpoint"
  default     = "api.staging-sfo1.inferadb.io"
}

# Load all region configurations (static module source)
module "regions" {
  source = "../../modules/regions"
}

# Select the appropriate region configs
locals {
  nyc1_config = module.regions.all["nyc1"]
  sfo1_config = module.regions.all["sfo1"]
}

# Staging NYC1 cluster
module "staging_nyc1" {
  source = "../../modules/talos-cluster"

  cluster_name              = "inferadb-staging-nyc1"
  cluster_endpoint_hostname = var.cluster_endpoint_hostname_nyc1
  provider_type             = var.provider_type
  region                    = "nyc1"
  provider_region           = lookup(local.nyc1_config.region_mappings, var.provider_type, "us-east-1")
  environment               = "staging"

  # Production-like configuration but smaller
  control_plane_count = 3
  worker_count        = 3
  worker_machine_type = "medium"

  # Use spot instances for stateless workloads
  use_spot_instances = true
  spot_max_price     = ""

  # Talos and Kubernetes versions
  talos_version      = "v1.8.0"
  kubernetes_version = "1.30.0"

  # Network configuration
  vpc_id     = var.vpc_id_nyc1
  subnet_ids = var.subnet_ids_nyc1

  tags = {
    Purpose    = "staging"
    CostCenter = "engineering"
    Terraform  = "true"
    Region     = "nyc1"
  }
}

# Staging SFO1 cluster (optional for multi-region testing)
module "staging_sfo1" {
  source = "../../modules/talos-cluster"
  count  = var.enable_multi_region ? 1 : 0

  cluster_name              = "inferadb-staging-sfo1"
  cluster_endpoint_hostname = var.cluster_endpoint_hostname_sfo1
  provider_type             = var.provider_type
  region                    = "sfo1"
  provider_region           = lookup(local.sfo1_config.region_mappings, var.provider_type, "us-west-1")
  environment               = "staging"

  # Production-like configuration but smaller
  control_plane_count = 3
  worker_count        = 3
  worker_machine_type = "medium"

  # Use spot instances for stateless workloads
  use_spot_instances = true
  spot_max_price     = ""

  # Talos and Kubernetes versions
  talos_version      = "v1.8.0"
  kubernetes_version = "1.30.0"

  # Network configuration
  vpc_id     = var.vpc_id_sfo1
  subnet_ids = var.subnet_ids_sfo1

  tags = {
    Purpose    = "staging"
    CostCenter = "engineering"
    Terraform  = "true"
    Region     = "sfo1"
  }
}

# Variables
variable "enable_multi_region" {
  type        = bool
  description = "Enable multi-region deployment (NYC1 + SFO1)"
  default     = false
}

variable "vpc_id_nyc1" {
  type        = string
  description = "VPC ID for NYC1 cluster"
  default     = ""
}

variable "subnet_ids_nyc1" {
  type        = list(string)
  description = "Subnet IDs for NYC1 cluster"
  default     = []
}

variable "vpc_id_sfo1" {
  type        = string
  description = "VPC ID for SFO1 cluster"
  default     = ""
}

variable "subnet_ids_sfo1" {
  type        = list(string)
  description = "Subnet IDs for SFO1 cluster"
  default     = []
}

# Outputs
output "nyc1_kubeconfig" {
  description = "Kubeconfig for staging NYC1 cluster"
  value       = module.staging_nyc1.kubeconfig
  sensitive   = true
}

output "nyc1_cluster_endpoint" {
  description = "NYC1 cluster endpoint"
  value       = module.staging_nyc1.cluster_endpoint
}

output "sfo1_kubeconfig" {
  description = "Kubeconfig for staging SFO1 cluster"
  value       = var.enable_multi_region ? module.staging_sfo1[0].kubeconfig : null
  sensitive   = true
}

output "sfo1_cluster_endpoint" {
  description = "SFO1 cluster endpoint"
  value       = var.enable_multi_region ? module.staging_sfo1[0].cluster_endpoint : null
}
