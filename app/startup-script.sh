#!/bin/bash
# =============================================================================
# VM Startup Script
# This script is executed on VM startup to configure the application
# =============================================================================

set -e

# Logging
exec > >(tee /var/log/startup-script.log) 2>&1
echo "Starting VM configuration at $(date)"

# Install required packages
apt-get update
apt-get install -y python3-pip python3-venv nginx curl jq

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install flask gunicorn

# Create application file
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
REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
    -H "Metadata-Flavor: Google" | cut -d'/' -f4 | cut -d'-' -f1-2)

# Create systemd service
cat > /etc/systemd/system/dr-app.service << SERVICEEOF
[Unit]
Description=DR Lab Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
Environment=REGION=${REGION}
ExecStart=/opt/app/venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 main:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Start application service
systemctl daemon-reload
systemctl enable dr-app
systemctl start dr-app

# Configure nginx as reverse proxy
cat > /etc/nginx/sites-available/dr-app << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /health {
        proxy_pass http://127.0.0.1:8080/health;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/dr-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

echo "Startup script completed successfully at $(date)"
