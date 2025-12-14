output "kubeconfig" {
  description = "Kubeconfig for accessing the Kubernetes cluster"
  value       = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talosconfig for managing Talos nodes"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = local.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value       = local.control_plane_ips
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = local.worker_ips
}
