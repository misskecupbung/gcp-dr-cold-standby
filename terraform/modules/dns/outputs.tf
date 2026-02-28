# =============================================================================
# DNS Module - Outputs
# =============================================================================

output "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone"
  value       = google_dns_managed_zone.main.name
}

output "dns_name_servers" {
  description = "The list of name servers for the DNS zone"
  value       = google_dns_managed_zone.main.name_servers
}

output "primary_record_name" {
  description = "The DNS name of the primary region A record"
  value       = google_dns_record_set.primary.name
}

output "standby_record_name" {
  description = "The DNS name of the standby region A record"
  value       = google_dns_record_set.standby.name
}

output "main_record_name" {
  description = "The DNS name of the main application A record"
  value       = google_dns_record_set.app.name
}
