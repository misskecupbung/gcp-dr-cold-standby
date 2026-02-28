# =============================================================================
# Compute Module - Outputs
# =============================================================================

output "mig_id" {
  description = "The ID of the managed instance group"
  value       = google_compute_region_instance_group_manager.app.id
}

output "mig_name" {
  description = "The name of the managed instance group"
  value       = google_compute_region_instance_group_manager.app.name
}

output "mig_self_link" {
  description = "The self link of the managed instance group"
  value       = google_compute_region_instance_group_manager.app.self_link
}

output "instance_template_id" {
  description = "The ID of the instance template"
  value       = google_compute_instance_template.app.id
}

output "instance_template_name" {
  description = "The name of the instance template"
  value       = google_compute_instance_template.app.name
}

output "health_check_id" {
  description = "The ID of the health check"
  value       = google_compute_health_check.app.id
}

output "service_account_email" {
  description = "The email address of the service account used by instances"
  value       = google_service_account.compute_sa.email
}
