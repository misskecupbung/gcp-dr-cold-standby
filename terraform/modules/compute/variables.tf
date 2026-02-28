# =============================================================================
# Compute Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for compute resources"
  type        = string
}

variable "zone" {
  description = "The GCP zone within the region for zonal resources"
  type        = string
}

variable "network_id" {
  description = "The ID of the VPC network to attach instances to"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet to attach instances to"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary region (true) or standby region (false)"
  type        = bool
}

variable "machine_type" {
  description = "The machine type for compute instances (e.g., n2-standard-2)"
  type        = string
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
}

variable "data_disk_size" {
  description = "Size of the data disk in GB"
  type        = number
}

variable "image_family" {
  description = "The image family to use for instances (e.g., debian-12)"
  type        = string
}

variable "image_project" {
  description = "The project containing the image family (e.g., debian-cloud)"
  type        = string
}

variable "network_tags" {
  description = "Network tags to apply to instances for firewall rules"
  type        = list(string)
}

variable "min_replicas" {
  description = "Minimum number of instances in the managed instance group"
  type        = number
}

variable "max_replicas" {
  description = "Maximum number of instances in the managed instance group"
  type        = number
}

variable "target_cpu" {
  description = "Target CPU utilization for autoscaling (0.0 to 1.0)"
  type        = number
}

variable "health_check_port" {
  description = "Port number for health check requests"
  type        = number
}

variable "health_check_path" {
  description = "URL path for health check requests (e.g., /health)"
  type        = string
}

variable "snapshot_policy_id" {
  description = "The ID of the snapshot policy to attach to data disks (null for standby)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to all compute resources"
  type        = map(string)
  default     = {}
}

variable "name_suffix" {
  description = "Random suffix to append to resource names for uniqueness"
  type        = string
}
