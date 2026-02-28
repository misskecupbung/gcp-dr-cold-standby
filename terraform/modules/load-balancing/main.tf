# =============================================================================
# Load Balancing Module - Global HTTP(S) Load Balancer
# =============================================================================

# =============================================================================
# Global Health Check
# =============================================================================
resource "google_compute_health_check" "global" {
  name    = "dr-global-health-check-${var.name_suffix}"
  project = var.project_id

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }

  log_config {
    enable = true
  }
}

# =============================================================================
# Backend Service - Primary Region
# =============================================================================
resource "google_compute_backend_service" "primary" {
  name                  = "dr-backend-primary-${var.name_suffix}"
  project               = var.project_id
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.global.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = var.primary_mig_id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  connection_draining_timeout_sec = 300
}

# =============================================================================
# Backend Service - Standby Region
# =============================================================================
resource "google_compute_backend_service" "standby" {
  name                  = "dr-backend-standby-${var.name_suffix}"
  project               = var.project_id
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.global.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = var.standby_mig_id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  connection_draining_timeout_sec = 300
}

# =============================================================================
# URL Map with Failover
# =============================================================================
resource "google_compute_url_map" "default" {
  name            = "dr-url-map-${var.name_suffix}"
  project         = var.project_id
  default_service = google_compute_backend_service.primary.id

  # Host rules for different paths
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.primary.id

    route_rules {
      priority = 1
      match_rules {
        prefix_match = "/"
      }
      route_action {
        weighted_backend_services {
          backend_service = google_compute_backend_service.primary.id
          weight          = 100
        }
        # Failover to standby
        retry_policy {
          retry_conditions = ["5xx", "reset", "connect-failure", "retriable-4xx"]
          num_retries      = 3
          per_try_timeout {
            seconds = 10
          }
        }
      }
    }
  }
}

# =============================================================================
# Target HTTP Proxy
# =============================================================================
resource "google_compute_target_http_proxy" "default" {
  name    = "dr-http-proxy-${var.name_suffix}"
  project = var.project_id
  url_map = google_compute_url_map.default.id
}

# =============================================================================
# Global External IP Address
# =============================================================================
resource "google_compute_global_address" "default" {
  name         = "dr-lb-ip-${var.name_suffix}"
  project      = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# =============================================================================
# Global Forwarding Rule
# =============================================================================
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "dr-http-forwarding-rule-${var.name_suffix}"
  project               = var.project_id
  target                = google_compute_target_http_proxy.default.id
  port_range            = "80"
  ip_address            = google_compute_global_address.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}
