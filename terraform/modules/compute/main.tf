# Compute module - instance templates and managed instance groups

locals {
  role_prefix = var.is_primary ? "primary" : "standby"
}

resource "google_service_account" "compute_sa" {
  account_id   = "dr-${local.role_prefix}-sa-${var.name_suffix}"
  display_name = "DR ${title(local.role_prefix)} Compute Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "compute_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/compute.instanceAdmin.v1",
    "roles/storage.objectViewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.compute_sa.email}"
}

resource "google_compute_instance_template" "app" {
  name_prefix  = "dr-${local.role_prefix}-template-"
  project      = var.project_id
  region       = var.region
  machine_type = var.machine_type

  tags = var.network_tags

  labels = merge(var.labels, {
    role   = local.role_prefix
    region = var.region
  })

  disk {
    source_image = "projects/${var.image_project}/global/images/family/${var.image_family}"
    disk_size_gb = var.boot_disk_size
    disk_type    = "pd-balanced"
    auto_delete  = true
    boot         = true
  }

  # Data disk
  disk {
    disk_size_gb = var.data_disk_size
    disk_type    = "pd-balanced"
    auto_delete  = false
    boot         = false
    device_name  = "data-disk"
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id
    # No external IP - use NAT for outbound
  }

  service_account {
    email  = google_service_account.compute_sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
      #!/bin/bash
      set -e
      
      # Install required packages
      apt-get update
      apt-get install -y python3-pip python3-venv nginx curl jq

      # Create application directory
      mkdir -p /opt/app
      cd /opt/app

      # Create virtual environment
      python3 -m venv venv
      source venv/bin/activate

      # Install Flask
      pip install flask gunicorn

      # Create application
      cat > /opt/app/main.py << 'APPEOF'
      from flask import Flask, jsonify
      import socket
      import os
      from datetime import datetime

      app = Flask(__name__)

      @app.route('/health')
      def health():
          return jsonify({
              'status': 'healthy',
              'hostname': socket.gethostname(),
              'timestamp': datetime.utcnow().isoformat(),
              'region': os.environ.get('REGION', 'unknown')
          })

      @app.route('/')
      def index():
          return jsonify({
              'message': 'DR Cold Standby Lab - Application Running',
              'hostname': socket.gethostname(),
              'region': os.environ.get('REGION', 'unknown'),
              'timestamp': datetime.utcnow().isoformat()
          })

      @app.route('/api/data')
      def data():
          return jsonify({
              'data': 'Sample data from the application',
              'hostname': socket.gethostname(),
              'region': os.environ.get('REGION', 'unknown')
          })

      if __name__ == '__main__':
          app.run(host='0.0.0.0', port=8080)
      APPEOF

      # Get region from metadata
      REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d'/' -f4 | cut -d'-' -f1-2)

      # Create systemd service
      cat > /etc/systemd/system/dr-app.service << SERVICEEOF
      [Unit]
      Description=DR Lab Application
      After=network.target

      [Service]
      Type=simple
      User=root
      WorkingDirectory=/opt/app
      Environment=REGION=$REGION
      ExecStart=/opt/app/venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 main:app
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
      SERVICEEOF

      # Start service
      systemctl daemon-reload
      systemctl enable dr-app
      systemctl start dr-app

      cat > /etc/nginx/sites-available/dr-app << 'NGINXEOF'
      server {
          listen 80;
          server_name _;

          location / {
              proxy_pass http://127.0.0.1:8080;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
          }
      }
      NGINXEOF

      ln -sf /etc/nginx/sites-available/dr-app /etc/nginx/sites-enabled/
      rm -f /etc/nginx/sites-enabled/default
      systemctl restart nginx

      echo "Startup complete" | logger -t startup-script
    EOF
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "app" {
  name    = "dr-${local.role_prefix}-health-check-${var.name_suffix}"
  project = var.project_id

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }

  log_config {
    enable = true
  }
}

resource "google_compute_region_instance_group_manager" "app" {
  name    = "dr-${local.role_prefix}-mig-${var.name_suffix}"
  project = var.project_id
  region  = var.region

  base_instance_name = "dr-${local.role_prefix}-vm"

  version {
    instance_template = google_compute_instance_template.app.id
  }

  target_size = var.min_replicas

  named_port {
    name = "http"
    port = var.health_check_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.app.id
    initial_delay_sec = 300
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 3
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }

  instance_lifecycle_policy {
    force_update_on_repair = "YES"
  }

  lifecycle {
    ignore_changes = [target_size]  # Allow autoscaler to manage
  }
}

resource "google_compute_region_autoscaler" "app" {
  name    = "dr-${local.role_prefix}-autoscaler-${var.name_suffix}"
  project = var.project_id
  region  = var.region
  target  = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 60

    cpu_utilization {
      target = var.target_cpu
    }

    scale_in_control {
      max_scaled_in_replicas {
        fixed = 1
      }
      time_window_sec = 300
    }
  }
}
