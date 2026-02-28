# =============================================================================
# DNS Module - Outputs
# =============================================================================

output "zone_name" {
  description = "The name of the Cloud DNS managed zone"
  value       = google_dns_managed_zone.primary.name
}

output "name_servers" {
  description = "The list of name servers for the DNS zone"
  value       = google_dns_managed_zone.primary.name_servers
}

output "dns_name" {
  description = "The DNS name of the zone"
  value       = google_dns_managed_zone.primary.dns_name
}

output "app_record_name" {
  description = "The DNS name of the main application A record"
  value       = google_dns_record_set.app.name
}
