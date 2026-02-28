# =============================================================================
# GCP DR Cold Standby Lab - Main Terraform Configuration
# =============================================================================

locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  
  labels = merge(var.labels, {
    environment = var.environment
    project     = "dr-cold-standby"
  })
}

# =============================================================================
# Random ID for unique naming
# =============================================================================
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# Enable Required APIs
# =============================================================================
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# Networking Module
# =============================================================================
module "networking" {
  source = "./modules/networking"

  project_id          = var.project_id
  network_name        = var.network_name
  primary_region      = var.primary_region
  standby_region      = var.standby_region
  primary_subnet_cidr = var.primary_subnet_cidr
  standby_subnet_cidr = var.standby_subnet_cidr
  labels              = local.labels

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Snapshot Policy Module
# =============================================================================
module "snapshot" {
  source = "./modules/snapshot"

  project_id                 = var.project_id
  primary_region             = var.primary_region
  standby_region             = var.standby_region
  snapshot_schedule_hours    = var.snapshot_schedule_hours
  snapshot_retention_days    = var.snapshot_retention_days
  snapshot_storage_locations = var.snapshot_storage_locations
  labels                     = local.labels

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Compute Module - Primary Region
# =============================================================================
module "compute_primary" {
  source = "./modules/compute"

  project_id           = var.project_id
  region               = var.primary_region
  zone                 = var.primary_zone
  network_id           = module.networking.network_id
  subnet_id            = module.networking.primary_subnet_id
  is_primary           = true
  
  # Instance Configuration
  machine_type         = var.machine_type_serving
  boot_disk_size       = var.boot_disk_size
  data_disk_size       = var.data_disk_size
  image_family         = var.image_family
  image_project        = var.image_project
  network_tags         = var.network_tags
  
  # Instance Group Configuration
  min_replicas         = var.primary_min_replicas
  max_replicas         = var.primary_max_replicas
  target_cpu           = var.target_cpu_utilization
  
  # Health Check Configuration
  health_check_port    = var.health_check_port
  health_check_path    = var.health_check_path
  
  # Snapshot Policy
  snapshot_policy_id   = module.snapshot.snapshot_policy_id
  
  # Labels
  labels               = local.labels
  name_suffix          = random_id.suffix.hex

  depends_on = [module.networking, module.snapshot]
}

# =============================================================================
# Compute Module - Standby Region (Cold Standby)
# =============================================================================
module "compute_standby" {
  source = "./modules/compute"

  project_id           = var.project_id
  region               = var.standby_region
  zone                 = var.standby_zone
  network_id           = module.networking.network_id
  subnet_id            = module.networking.standby_subnet_id
  is_primary           = false
  
  # Instance Configuration
  machine_type         = var.machine_type_serving
  boot_disk_size       = var.boot_disk_size
  data_disk_size       = var.data_disk_size
  image_family         = var.image_family
  image_project        = var.image_project
  network_tags         = var.network_tags
  
  # Instance Group Configuration (Cold Standby - 0 instances)
  min_replicas         = var.standby_min_replicas
  max_replicas         = var.standby_max_replicas
  target_cpu           = var.target_cpu_utilization
  
  # Health Check Configuration
  health_check_port    = var.health_check_port
  health_check_path    = var.health_check_path
  
  # No snapshot policy for standby
  snapshot_policy_id   = null
  
  # Labels
  labels               = local.labels
  name_suffix          = random_id.suffix.hex

  depends_on = [module.networking]
}

# =============================================================================
# Heartbeat Instance (Primary Region Only)
# =============================================================================
module "heartbeat" {
  source = "./modules/heartbeat"

  project_id            = var.project_id
  region                = var.primary_region
  zone                  = var.primary_zone
  network_id            = module.networking.network_id
  subnet_id             = module.networking.primary_subnet_id
  machine_type          = var.machine_type_heartbeat
  primary_mig_name      = module.compute_primary.mig_name
  standby_mig_name      = module.compute_standby.mig_name
  standby_region        = var.standby_region
  snapshot_policy_id    = module.snapshot.snapshot_policy_id
  labels                = local.labels
  name_suffix           = random_id.suffix.hex

  depends_on = [module.compute_primary, module.compute_standby]
}

# =============================================================================
# Load Balancing Module
# =============================================================================
module "load_balancing" {
  source = "./modules/load-balancing"

  project_id              = var.project_id
  primary_region          = var.primary_region
  standby_region          = var.standby_region
  primary_mig_id          = module.compute_primary.mig_id
  standby_mig_id          = module.compute_standby.mig_id
  health_check_port       = var.health_check_port
  health_check_path       = var.health_check_path
  health_check_interval   = var.health_check_interval
  health_check_timeout    = var.health_check_timeout
  healthy_threshold       = var.healthy_threshold
  unhealthy_threshold     = var.unhealthy_threshold
  labels                  = local.labels
  name_suffix             = random_id.suffix.hex

  depends_on = [module.compute_primary, module.compute_standby]
}

# =============================================================================
# DNS Module
# =============================================================================
module "dns" {
  source = "./modules/dns"

  project_id       = var.project_id
  dns_zone_name    = var.dns_zone_name
  domain_name      = var.domain_name
  dns_ttl          = var.dns_ttl
  lb_ip_address    = module.load_balancing.lb_ip_address
  labels           = local.labels

  depends_on = [module.load_balancing]
}

# =============================================================================
# Monitoring Module
# =============================================================================
module "monitoring" {
  count  = var.enable_monitoring ? 1 : 0
  source = "./modules/monitoring"

  project_id           = var.project_id
  notification_email   = var.notification_email
  primary_mig_name     = module.compute_primary.mig_name
  standby_mig_name     = module.compute_standby.mig_name
  lb_ip_address        = module.load_balancing.lb_ip_address
  domain_name          = var.domain_name
  uptime_check_period  = var.uptime_check_period
  health_check_port    = var.health_check_port
  health_check_path    = var.health_check_path

  depends_on = [module.load_balancing, module.dns]
}
