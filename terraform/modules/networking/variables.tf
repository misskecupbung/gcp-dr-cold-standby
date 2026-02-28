# =============================================================================
# Networking Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network to create"
  type        = string
}

variable "primary_region" {
  description = "Primary region for the DR setup (e.g., us-central1)"
  type        = string
}

variable "standby_region" {
  description = "Standby region for disaster recovery (e.g., us-east1)"
  type        = string
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary region subnet (e.g., 10.0.1.0/24)"
  type        = string
}

variable "standby_subnet_cidr" {
  description = "CIDR range for the standby region subnet (e.g., 10.0.2.0/24)"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all networking resources"
  type        = map(string)
  default     = {}
}
