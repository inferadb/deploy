variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster"
}

variable "provider_type" {
  type        = string
  description = "Cloud provider: aws, gcp, digitalocean"
  validation {
    condition     = contains(["aws", "gcp", "digitalocean"], var.provider_type)
    error_message = "Provider type must be one of: aws, gcp, digitalocean"
  }
}

variable "region" {
  type        = string
  description = "InferaDB region identifier (e.g., nyc1, sfo1)"
}

variable "provider_region" {
  type        = string
  description = "Provider-specific region (e.g., us-east-1, us-west1)"
}

variable "control_plane_count" {
  type        = number
  default     = 3
  description = "Number of control plane nodes"
}

variable "worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes"
}

variable "worker_machine_type" {
  type        = string
  default     = "medium"
  description = "Machine type for workers: small, medium, large"
  validation {
    condition     = contains(["small", "medium", "large"], var.worker_machine_type)
    error_message = "Worker machine type must be one of: small, medium, large"
  }
}

variable "use_spot_instances" {
  type        = bool
  default     = false
  description = "Use spot/preemptible instances for stateless workers (60-70% cost savings)"
}

variable "spot_max_price" {
  type        = string
  default     = ""
  description = "Maximum spot price (empty = on-demand price cap). AWS only."
}

variable "talos_version" {
  type        = string
  default     = "v1.8.0"
  description = "Talos Linux version"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.30.0"
  description = "Kubernetes version"
}

variable "environment" {
  type        = string
  description = "Environment name: dev, staging, production"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production"
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the cluster (provider-specific)"
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for worker nodes"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to resources"
  default     = {}
}

variable "cluster_endpoint_hostname" {
  type        = string
  description = "Pre-allocated hostname for cluster API endpoint (e.g., api.nyc1.inferadb.io). Required to break dependency cycle."
}
