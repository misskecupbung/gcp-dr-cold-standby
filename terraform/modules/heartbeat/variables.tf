# =============================================================================
# Heartbeat Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where heartbeat resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name used for naming resources (e.g., dev, staging, prod)"
  type        = string
}

variable "primary_region" {
  description = "The primary GCP region to monitor"
  type        = string
}

variable "standby_region" {
  description = "The standby GCP region for failover"
  type        = string
}

variable "network" {
  description = "The VPC network self link for the heartbeat instances"
  type        = string
}

variable "primary_subnet" {
  description = "The primary region subnet self link for heartbeat instances"
  type        = string
}

variable "standby_subnet" {
  description = "The standby region subnet self link for heartbeat instances"
  type        = string
}

variable "machine_type" {
  description = "The machine type for heartbeat monitoring instances"
  type        = string
  default     = "e2-micro"
}

variable "health_check_endpoint" {
  description = "The HTTP endpoint path for health checks"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "The interval in seconds between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "The timeout in seconds for each health check"
  type        = number
  default     = 10
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failures before marking instance as unhealthy"
  type        = number
  default     = 3
}

variable "lb_ip_address" {
  description = "The load balancer IP address to monitor"
  type        = string
}

variable "primary_mig_self_link" {
  description = "The self link of the primary managed instance group"
  type        = string
}

variable "standby_mig_self_link" {
  description = "The self link of the standby managed instance group"
  type        = string
}

variable "notification_email" {
  description = "Email address for health check failure notifications"
  type        = string
  default     = ""
}

variable "service_account_email" {
  description = "Service account email for heartbeat instances"
  type        = string
}
