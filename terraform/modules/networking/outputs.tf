# =============================================================================
# Networking Module - Outputs
# =============================================================================

output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "The self link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "primary_subnet_id" {
  description = "The ID of the primary region subnet"
  value       = google_compute_subnetwork.primary.id
}

output "primary_subnet_name" {
  description = "The name of the primary region subnet"
  value       = google_compute_subnetwork.primary.name
}

output "standby_subnet_id" {
  description = "The ID of the standby region subnet"
  value       = google_compute_subnetwork.standby.id
}

output "standby_subnet_name" {
  description = "The name of the standby region subnet"
  value       = google_compute_subnetwork.standby.name
}
