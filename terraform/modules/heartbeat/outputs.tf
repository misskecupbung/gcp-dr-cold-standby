# =============================================================================
# Heartbeat Module - Outputs
# =============================================================================

output "heartbeat_instance_template" {
  description = "The self link of the heartbeat instance template"
  value       = google_compute_instance_template.heartbeat.self_link
}

output "heartbeat_primary_mig" {
  description = "The self link of the primary region heartbeat managed instance group"
  value       = google_compute_region_instance_group_manager.heartbeat_primary.self_link
}

output "heartbeat_standby_mig" {
  description = "The self link of the standby region heartbeat managed instance group"
  value       = google_compute_region_instance_group_manager.heartbeat_standby.self_link
}

output "health_check_id" {
  description = "The ID of the heartbeat health check"
  value       = google_compute_health_check.heartbeat.id
}

output "uptime_check_id" {
  description = "The ID of the Cloud Monitoring uptime check"
  value       = google_monitoring_uptime_check_config.primary.id
}
