# =============================================================================
# Load Balancing Module - Outputs
# =============================================================================

output "lb_ip_address" {
  description = "The external IP address of the global load balancer"
  value       = google_compute_global_address.default.address
}

output "lb_ip_name" {
  description = "The name of the global IP address resource"
  value       = google_compute_global_address.default.name
}

output "url_map_id" {
  description = "The ID of the URL map"
  value       = google_compute_url_map.default.id
}

output "primary_backend_id" {
  description = "The ID of the primary region backend service"
  value       = google_compute_backend_service.primary.id
}

output "standby_backend_id" {
  description = "The ID of the standby region backend service"
  value       = google_compute_backend_service.standby.id
}

output "health_check_id" {
  description = "The ID of the global health check"
  value       = google_compute_health_check.global.id
}
