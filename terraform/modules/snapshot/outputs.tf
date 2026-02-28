# =============================================================================
# Snapshot Module - Outputs
# =============================================================================

output "snapshot_policy_id" {
  description = "The ID of the resource policy for snapshot scheduling"
  value       = google_compute_resource_policy.snapshot_schedule.id
}

output "snapshot_policy_name" {
  description = "The name of the resource policy for snapshot scheduling"
  value       = google_compute_resource_policy.snapshot_schedule.name
}

output "snapshot_schedule_hours" {
  description = "The configured interval in hours between automated snapshots"
  value       = var.snapshot_schedule_hours
}

output "snapshot_retention_days" {
  description = "The configured number of days snapshots are retained"
  value       = var.snapshot_retention_days
}

output "snapshot_storage_locations" {
  description = "The storage locations for the snapshots"
  value       = google_compute_resource_policy.snapshot_schedule.snapshot_schedule_policy[0].snapshot_properties[0].storage_locations
}
