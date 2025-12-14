terraform {
  required_version = ">= 1.5.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}
