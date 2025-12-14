# SFO1 Region Outputs

output "region_mappings" {
  description = "Provider-specific region mappings for SFO1"
  value       = local.region_mappings
}

output "machine_type_mappings" {
  description = "Machine type mappings across providers"
  value       = local.machine_type_mappings
}

output "region_config" {
  description = "Region configuration metadata"
  value       = local.region_config
}
