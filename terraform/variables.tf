# =============================================================================
# Project Configuration
# =============================================================================
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Human-readable project name"
  type        = string
  default     = "DR Cold Standby Lab"
}

# =============================================================================
# Region Configuration
# =============================================================================
variable "primary_region" {
  description = "Primary region for the application"
  type        = string
  default     = "us-central1"
}

variable "primary_zone" {
  description = "Primary zone within the primary region"
  type        = string
  default     = "us-central1-a"
}

variable "standby_region" {
  description = "Standby region for disaster recovery"
  type        = string
  default     = "us-east1"
}

variable "standby_zone" {
  description = "Standby zone within the standby region"
  type        = string
  default     = "us-east1-b"
}

# =============================================================================
# Networking Configuration
# =============================================================================
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "dr-vpc"
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary region subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "standby_subnet_cidr" {
  description = "CIDR range for the standby region subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# =============================================================================
# Compute Configuration
# =============================================================================
variable "machine_type_serving" {
  description = "Machine type for serving instances"
  type        = string
  default     = "n2-standard-2"
}

variable "machine_type_heartbeat" {
  description = "Machine type for heartbeat instance"
  type        = string
  default     = "e2-small"
}

variable "boot_disk_size" {
  description = "Size of boot disk in GB"
  type        = number
  default     = 20
}

variable "data_disk_size" {
  description = "Size of data disk in GB"
  type        = number
  default     = 100
}

variable "image_family" {
  description = "Image family for VMs"
  type        = string
  default     = "debian-12"
}

variable "image_project" {
  description = "Project containing the image"
  type        = string
  default     = "debian-cloud"
}

# =============================================================================
# Instance Group Configuration
# =============================================================================
variable "primary_min_replicas" {
  description = "Minimum number of instances in primary MIG"
  type        = number
  default     = 2
}

variable "primary_max_replicas" {
  description = "Maximum number of instances in primary MIG"
  type        = number
  default     = 5
}

variable "standby_min_replicas" {
  description = "Minimum number of instances in standby MIG (cold standby = 0)"
  type        = number
  default     = 0
}

variable "standby_max_replicas" {
  description = "Maximum number of instances in standby MIG"
  type        = number
  default     = 5
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 0.7
}

# =============================================================================
# Health Check Configuration
# =============================================================================
variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path for HTTP health checks"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Number of consecutive successes to mark healthy"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failures to mark unhealthy"
  type        = number
  default     = 3
}

# =============================================================================
# DNS Configuration
# =============================================================================
variable "dns_zone_name" {
  description = "Name of the Cloud DNS managed zone"
  type        = string
  default     = "dr-lab-zone"
}

variable "domain_name" {
  description = "Domain name for the application (must end with a dot)"
  type        = string
  default     = "dr-lab.example.com."
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 300
}

variable "enable_dns" {
  description = "Enable Cloud DNS (requires a registered domain)"
  type        = bool
  default     = false
}

# =============================================================================
# Snapshot Configuration
# =============================================================================
variable "snapshot_schedule_hours" {
  description = "Hours between snapshots"
  type        = number
  default     = 1
}

variable "snapshot_retention_days" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 7
}

# =============================================================================
# Monitoring Configuration
# =============================================================================
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for alerting notifications"
  type        = string
  default     = ""
}

variable "uptime_check_period" {
  description = "Period between uptime checks in seconds"
  type        = string
  default     = "60s"
}

# =============================================================================
# Labels and Tags
# =============================================================================
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "lab"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "dr-lab"
  }
}

variable "network_tags" {
  description = "Network tags for firewall rules"
  type        = list(string)
  default     = ["dr-app", "http-server", "https-server"]
}
