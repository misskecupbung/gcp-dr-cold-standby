# =============================================================================
# DNS Module - Cloud DNS Configuration
# =============================================================================

# =============================================================================
# Cloud DNS Managed Zone
# =============================================================================
resource "google_dns_managed_zone" "primary" {
  name        = var.dns_zone_name
  project     = var.project_id
  dns_name    = var.domain_name
  description = "DR Cold Standby Lab DNS Zone"

  visibility = "public"

  dnssec_config {
    state = "on"
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# =============================================================================
# A Record - Points to Load Balancer
# =============================================================================
resource "google_dns_record_set" "app" {
  name         = var.domain_name
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.primary.name
  project      = var.project_id

  rrdatas = [var.lb_ip_address]
}

# =============================================================================
# CNAME Record - www subdomain
# =============================================================================
resource "google_dns_record_set" "www" {
  name         = "www.${var.domain_name}"
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.primary.name
  project      = var.project_id

  rrdatas = [var.domain_name]
}
