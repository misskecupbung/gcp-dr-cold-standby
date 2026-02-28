# =============================================================================
# Monitoring Module - Outputs
# =============================================================================

output "notification_channel_id" {
  description = "The ID of the email notification channel"
  value       = google_monitoring_notification_channel.email.id
}

output "notification_channel_name" {
  description = "The display name of the email notification channel"
  value       = google_monitoring_notification_channel.email.display_name
}

output "cpu_alert_policy_id" {
  description = "The ID of the CPU utilization alert policy"
  value       = google_monitoring_alert_policy.cpu_utilization.id
}

output "uptime_alert_policy_id" {
  description = "The ID of the uptime check alert policy"
  value       = google_monitoring_alert_policy.uptime_check.id
}

output "uptime_check_id" {
  description = "The ID of the load balancer uptime check"
  value       = google_monitoring_uptime_check_config.lb_check.id
}

output "dashboard_id" {
  description = "The ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.dashboard_enabled ? google_monitoring_dashboard.dr_dashboard[0].id : null
}
