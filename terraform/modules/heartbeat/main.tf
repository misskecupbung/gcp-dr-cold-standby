# =============================================================================
# Heartbeat Module - Health Monitoring and Snapshot Management
# =============================================================================

# =============================================================================
# Service Account for Heartbeat Instance
# =============================================================================
resource "google_service_account" "heartbeat" {
  account_id   = "dr-heartbeat-sa-${var.name_suffix}"
  display_name = "DR Heartbeat Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "heartbeat_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/compute.storageAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/storage.objectAdmin",
    "roles/dns.admin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.heartbeat.email}"
}

# =============================================================================
# Heartbeat Instance
# =============================================================================
resource "google_compute_instance" "heartbeat" {
  name         = "dr-heartbeat-${var.name_suffix}"
  project      = var.project_id
  zone         = var.zone
  machine_type = var.machine_type

  tags = ["dr-app", "heartbeat"]

  labels = merge(var.labels, {
    role = "heartbeat"
  })

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id
  }

  service_account {
    email  = google_service_account.heartbeat.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin     = "TRUE"
    PRIMARY_MIG        = var.primary_mig_name
    STANDBY_MIG        = var.standby_mig_name
    PRIMARY_REGION     = var.region
    STANDBY_REGION     = var.standby_region
    PROJECT_ID         = var.project_id
    SNAPSHOT_POLICY_ID = var.snapshot_policy_id

    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # Install required packages
      apt-get update
      apt-get install -y curl jq cron python3-pip

      # Install gcloud if not present
      if ! command -v gcloud &> /dev/null; then
        curl https://sdk.cloud.google.com | bash -s -- --disable-prompts
        source /root/google-cloud-sdk/path.bash.inc
      fi

      # Create heartbeat monitoring directory
      mkdir -p /opt/heartbeat
      mkdir -p /var/log/heartbeat

      # Create heartbeat monitoring script
      cat > /opt/heartbeat/heartbeat.sh << 'HEARTBEATEOF'
      #!/bin/bash
      set -e

      # Load metadata
      PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PROJECT_ID" -H "Metadata-Flavor: Google")
      PRIMARY_MIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_MIG" -H "Metadata-Flavor: Google")
      STANDBY_MIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/STANDBY_MIG" -H "Metadata-Flavor: Google")
      PRIMARY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_REGION" -H "Metadata-Flavor: Google")
      STANDBY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/STANDBY_REGION" -H "Metadata-Flavor: Google")

      LOG_FILE="/var/log/heartbeat/heartbeat.log"
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      log() {
        echo "$TIMESTAMP - $1" >> $LOG_FILE
      }

      # Check primary MIG health
      check_primary_health() {
        HEALTHY_COUNT=$(gcloud compute instance-groups managed list-instances $PRIMARY_MIG \
          --region=$PRIMARY_REGION \
          --project=$PROJECT_ID \
          --filter="status=RUNNING" \
          --format="value(instance)" 2>/dev/null | wc -l)
        
        echo $HEALTHY_COUNT
      }

      # Main health check
      HEALTHY=$(check_primary_health)
      log "Primary MIG healthy instances: $HEALTHY"

      if [ "$HEALTHY" -lt 1 ]; then
        log "WARNING: Primary region unhealthy. Consider failover."
        
        # Send custom metric to Cloud Monitoring
        gcloud monitoring metrics write \
          --project=$PROJECT_ID \
          custom.googleapis.com/dr/primary_healthy \
          --value=0 \
          --type=gauge \
          2>/dev/null || true
      else
        gcloud monitoring metrics write \
          --project=$PROJECT_ID \
          custom.googleapis.com/dr/primary_healthy \
          --value=$HEALTHY \
          --type=gauge \
          2>/dev/null || true
      fi

      log "Heartbeat check completed"
      HEARTBEATEOF

      chmod +x /opt/heartbeat/heartbeat.sh

      # Create snapshot management script
      cat > /opt/heartbeat/snapshot-manager.sh << 'SNAPSHOTEOF'
      #!/bin/bash
      set -e

      PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PROJECT_ID" -H "Metadata-Flavor: Google")
      LOG_FILE="/var/log/heartbeat/snapshot.log"
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      log() {
        echo "$TIMESTAMP - $1" >> $LOG_FILE
      }

      # List recent snapshots
      log "Checking recent snapshots..."
      SNAPSHOTS=$(gcloud compute snapshots list \
        --project=$PROJECT_ID \
        --filter="creationTimestamp>=$(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
        --format="table(name,diskSizeGb,status,creationTimestamp)" 2>/dev/null)

      log "Recent snapshots: $SNAPSHOTS"

      # Verify snapshot policy is working
      POLICY_SNAPSHOTS=$(gcloud compute snapshots list \
        --project=$PROJECT_ID \
        --filter="labels.snapshot_policy:dr-snapshot-policy" \
        --limit=5 \
        --format="value(name)" 2>/dev/null)

      if [ -n "$POLICY_SNAPSHOTS" ]; then
        log "Snapshot policy is working. Recent policy snapshots found."
      else
        log "WARNING: No recent policy-based snapshots found."
      fi

      log "Snapshot check completed"
      SNAPSHOTEOF

      chmod +x /opt/heartbeat/snapshot-manager.sh

      # Set up cron jobs
      (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/heartbeat/heartbeat.sh") | crontab -
      (crontab -l 2>/dev/null; echo "*/15 * * * * /opt/heartbeat/snapshot-manager.sh") | crontab -

      # Log completion
      echo "Heartbeat instance setup completed" | logger -t startup-script
    EOF
  }

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [metadata["ssh-keys"]]
  }
}
