# =============================================================================
# Monitoring Module - Outputs
# =============================================================================

output "notification_channel_id" {
  description = "The ID of the email notification channel"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

output "notification_channel_name" {
  description = "The display name of the email notification channel"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email[0].display_name : null
}

output "primary_down_alert_policy_id" {
  description = "The ID of the primary down alert policy"
  value       = google_monitoring_alert_policy.primary_down.id
}

output "uptime_alert_policy_id" {
  description = "The ID of the uptime check alert policy"
  value       = google_monitoring_alert_policy.uptime_failed.id
}

output "uptime_check_id" {
  description = "The ID of the load balancer uptime check"
  value       = google_monitoring_uptime_check_config.lb_health.id
}

output "dashboard_id" {
  description = "The ID of the Cloud Monitoring dashboard"
  value       = google_monitoring_dashboard.dr_dashboard.id
}
