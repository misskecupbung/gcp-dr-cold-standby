# =============================================================================
# Monitoring Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where monitoring resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name used for naming resources (e.g., dev, staging, prod)"
  type        = string
}

variable "primary_region" {
  description = "The primary GCP region being monitored"
  type        = string
}

variable "standby_region" {
  description = "The standby GCP region being monitored"
  type        = string
}

variable "notification_email" {
  description = "Email address for alerting notifications"
  type        = string
}

variable "primary_mig_name" {
  description = "The name of the primary managed instance group for monitoring"
  type        = string
}

variable "standby_mig_name" {
  description = "The name of the standby managed instance group for monitoring"
  type        = string
}

variable "lb_url" {
  description = "The URL of the load balancer for uptime monitoring"
  type        = string
}

variable "alert_cpu_threshold" {
  description = "CPU utilization percentage threshold for alerting"
  type        = number
  default     = 80
}

variable "alert_memory_threshold" {
  description = "Memory utilization percentage threshold for alerting"
  type        = number
  default     = 80
}

variable "uptime_check_period" {
  description = "Period in seconds between uptime checks"
  type        = string
  default     = "60s"
}

variable "uptime_check_timeout" {
  description = "Timeout in seconds for uptime checks"
  type        = string
  default     = "10s"
}

variable "dashboard_enabled" {
  description = "Whether to create a Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "log_based_metrics_enabled" {
  description = "Whether to create log-based metrics for error tracking"
  type        = bool
  default     = true
}
