# =============================================================================
# Snapshot Module - Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where snapshot resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name used for naming resources (e.g., dev, staging, prod)"
  type        = string
}

variable "primary_region" {
  description = "The primary GCP region where source disks are located"
  type        = string
}

variable "standby_region" {
  description = "The standby GCP region where snapshots will be stored"
  type        = string
}

variable "snapshot_schedule_hours" {
  description = "Interval in hours between automated disk snapshots (affects RPO)"
  type        = number
  default     = 1
}

variable "snapshot_retention_days" {
  description = "Number of days to retain automated disk snapshots"
  type        = number
  default     = 7
}

variable "primary_disk_name" {
  description = "The name of the primary disk to snapshot"
  type        = string
  default     = ""
}

variable "primary_zone" {
  description = "The zone of the primary disk to snapshot"
  type        = string
  default     = ""
}

variable "snapshot_start_time" {
  description = "The time to start the snapshot schedule in HH:MM UTC format"
  type        = string
  default     = "04:00"
}
