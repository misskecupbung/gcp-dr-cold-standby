# =============================================================================
# Snapshot Module - Persistent Disk Snapshot Policies
# =============================================================================

# =============================================================================
# Snapshot Schedule Policy
# =============================================================================
resource "google_compute_resource_policy" "snapshot_schedule" {
  name    = "dr-snapshot-policy"
  project = var.project_id
  region  = var.primary_region

  snapshot_schedule_policy {
    schedule {
      hourly_schedule {
        hours_in_cycle = var.snapshot_schedule_hours
        start_time     = "00:00"
      }
    }

    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels            = var.labels
      storage_locations = var.snapshot_storage_locations
      guest_flush       = false
    }
  }
}

# =============================================================================
# Storage Bucket for Snapshot Metadata (used by heartbeat system)
# =============================================================================
resource "google_storage_bucket" "snapshot_metadata" {
  name          = "${var.project_id}-dr-snapshot-metadata"
  project       = var.project_id
  location      = "US"
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}
