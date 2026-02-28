# =============================================================================
# DNS Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where DNS resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name used for naming resources (e.g., dev, staging, prod)"
  type        = string
}

variable "domain_name" {
  description = "The domain name for the DNS zone (e.g., example.com)"
  type        = string
}

variable "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone resource"
  type        = string
}

variable "lb_ip_address" {
  description = "The IP address of the load balancer to point DNS records to"
  type        = string
}

variable "primary_region" {
  description = "The primary GCP region for DR architecture"
  type        = string
}

variable "standby_region" {
  description = "The standby GCP region for DR failover"
  type        = string
}

variable "primary_instance_group" {
  description = "The self link of the primary region managed instance group"
  type        = string
}

variable "standby_instance_group" {
  description = "The self link of the standby region managed instance group"
  type        = string
}
