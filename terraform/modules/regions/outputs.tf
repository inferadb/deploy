# Region Module Outputs

output "all" {
  description = "All region configurations indexed by region name"
  value       = local.all_regions
}

output "nyc1" {
  description = "NYC1 region configuration"
  value       = local.nyc1
}

output "sfo1" {
  description = "SFO1 region configuration"
  value       = local.sfo1
}

output "available_regions" {
  description = "List of available region names"
  value       = keys(local.all_regions)
}
