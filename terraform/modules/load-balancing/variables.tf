# =============================================================================
# Load Balancing Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "primary_region" {
  description = "Primary region for the DR setup"
  type        = string
}

variable "standby_region" {
  description = "Standby region for disaster recovery"
  type        = string
}

variable "primary_mig_id" {
  description = "The ID of the primary region managed instance group"
  type        = string
}

variable "standby_mig_id" {
  description = "The ID of the standby region managed instance group"
  type        = string
}

variable "health_check_port" {
  description = "Port number for health check requests"
  type        = number
}

variable "health_check_path" {
  description = "URL path for health check requests (e.g., /health)"
  type        = string
}

variable "health_check_interval" {
  description = "How often (in seconds) to perform health checks"
  type        = number
}

variable "health_check_timeout" {
  description = "How long (in seconds) to wait for a health check response"
  type        = number
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks to mark instance healthy"
  type        = number
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks to mark instance unhealthy"
  type        = number
}

variable "labels" {
  description = "Labels to apply to load balancing resources"
  type        = map(string)
  default     = {}
}

variable "name_suffix" {
  description = "Random suffix to append to resource names for uniqueness"
  type        = string
}
