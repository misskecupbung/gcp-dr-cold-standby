# =============================================================================
# Heartbeat Module - Health Monitoring System
# =============================================================================

# =============================================================================
# Instance Template for Heartbeat
# =============================================================================
resource "google_compute_instance_template" "heartbeat" {
  name_prefix  = "dr-heartbeat-"
  project      = var.project_id
  machine_type = var.machine_type
  region       = var.primary_region

  tags = ["heartbeat", "dr-app"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network    = var.network
    subnetwork = var.primary_subnet
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    PRIMARY_REGION         = var.primary_region
    STANDBY_REGION         = var.standby_region
    PROJECT_ID             = var.project_id
    LB_IP_ADDRESS          = var.lb_ip_address
    PRIMARY_MIG_SELF_LINK  = var.primary_mig_self_link
    STANDBY_MIG_SELF_LINK  = var.standby_mig_self_link
    HEALTH_CHECK_ENDPOINT  = var.health_check_endpoint
  }

  labels = {
    environment = var.environment
    role        = "heartbeat"
    managed-by  = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Health Check for Heartbeat Instances
# =============================================================================
resource "google_compute_health_check" "heartbeat" {
  name    = "dr-heartbeat-health-check"
  project = var.project_id

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  unhealthy_threshold = var.unhealthy_threshold
  healthy_threshold   = 2

  tcp_health_check {
    port = 22
  }
}

# =============================================================================
# Regional MIG - Primary Region Heartbeat
# =============================================================================
resource "google_compute_region_instance_group_manager" "heartbeat_primary" {
  name    = "dr-heartbeat-primary-mig"
  project = var.project_id
  region  = var.primary_region

  base_instance_name = "heartbeat-primary"

  version {
    instance_template = google_compute_instance_template.heartbeat.id
  }

  target_size = 1

  auto_healing_policies {
    health_check      = google_compute_health_check.heartbeat.id
    initial_delay_sec = 300
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 0
    max_unavailable_fixed = 1
  }
}

# =============================================================================
# Regional MIG - Standby Region Heartbeat
# =============================================================================
resource "google_compute_instance_template" "heartbeat_standby" {
  name_prefix  = "dr-heartbeat-standby-"
  project      = var.project_id
  machine_type = var.machine_type
  region       = var.standby_region

  tags = ["heartbeat", "dr-app"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network    = var.network
    subnetwork = var.standby_subnet
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    PRIMARY_REGION         = var.primary_region
    STANDBY_REGION         = var.standby_region
    PROJECT_ID             = var.project_id
    LB_IP_ADDRESS          = var.lb_ip_address
    PRIMARY_MIG_SELF_LINK  = var.primary_mig_self_link
    STANDBY_MIG_SELF_LINK  = var.standby_mig_self_link
    HEALTH_CHECK_ENDPOINT  = var.health_check_endpoint
  }

  labels = {
    environment = var.environment
    role        = "heartbeat-standby"
    managed-by  = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "heartbeat_standby" {
  name    = "dr-heartbeat-standby-mig"
  project = var.project_id
  region  = var.standby_region

  base_instance_name = "heartbeat-standby"

  version {
    instance_template = google_compute_instance_template.heartbeat_standby.id
  }

  target_size = 0

  auto_healing_policies {
    health_check      = google_compute_health_check.heartbeat.id
    initial_delay_sec = 300
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 0
    max_unavailable_fixed = 1
  }
}

# =============================================================================
# Cloud Monitoring Uptime Check
# =============================================================================
resource "google_monitoring_uptime_check_config" "primary" {
  display_name = "DR Heartbeat - Primary Region"
  project      = var.project_id
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = var.health_check_endpoint
    port         = "80"
    use_ssl      = false
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.lb_ip_address
    }
  }
}
