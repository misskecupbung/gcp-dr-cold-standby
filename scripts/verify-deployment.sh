#!/bin/bash
# =============================================================================
# Verify Deployment Script - Check Infrastructure Status
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "============================================================"
echo "   GCP DR Cold Standby Lab - Deployment Verification"
echo "============================================================"
echo ""

cd "$PROJECT_ROOT/terraform"

# Get outputs
log_info "Loading Terraform outputs..."
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)
PRIMARY_MIG=$(terraform output -raw primary_mig_name 2>/dev/null)
STANDBY_MIG=$(terraform output -raw standby_mig_name 2>/dev/null)
LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null)
DR_INFO=$(terraform output -json dr_recovery_info 2>/dev/null)
PRIMARY_REGION=$(echo "$DR_INFO" | jq -r '.primary_region')
STANDBY_REGION=$(echo "$DR_INFO" | jq -r '.standby_region')

echo ""
echo "Configuration:"
echo "  Project:        $PROJECT_ID"
echo "  Primary Region: $PRIMARY_REGION"
echo "  Standby Region: $STANDBY_REGION"
echo "  Load Balancer:  $LB_IP"
echo ""

# Check Primary MIG
log_info "Checking Primary Instance Group..."
PRIMARY_COUNT=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')

if [ "$PRIMARY_COUNT" -ge 1 ] 2>/dev/null; then
    log_success "Primary MIG: $PRIMARY_COUNT instances running"
    gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null
else
    log_warning "Primary MIG: No running instances"
fi
echo ""

# Check Standby MIG
log_info "Checking Standby Instance Group..."
STANDBY_COUNT=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
    --region="$STANDBY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')

if [ "$STANDBY_COUNT" -eq 0 ] 2>/dev/null; then
    log_success "Standby MIG: Cold standby (0 instances) - as expected"
else
    log_warning "Standby MIG: $STANDBY_COUNT instances (expected: 0 for cold standby)"
    gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null
fi
echo ""

# Check Load Balancer
log_info "Testing Load Balancer..."
echo ""

# HTTP health check
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" --connect-timeout 10 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    log_success "Load Balancer health endpoint: HTTP $HTTP_STATUS"
else
    log_warning "Load Balancer health endpoint: HTTP $HTTP_STATUS (may need more time)"
fi

# Application response
APP_RESPONSE=$(curl -s "http://$LB_IP/" --connect-timeout 10 2>/dev/null || echo "{}")
if echo "$APP_RESPONSE" | jq -e '.hostname' > /dev/null 2>&1; then
    HOSTNAME=$(echo "$APP_RESPONSE" | jq -r '.hostname')
    REGION=$(echo "$APP_RESPONSE" | jq -r '.region')
    log_success "Application responding from: $HOSTNAME ($REGION)"
else
    log_warning "Application not responding (may need more time to start)"
fi
echo ""

# Check Snapshots
log_info "Checking Snapshot Policy..."
SNAPSHOTS=$(gcloud compute snapshots list \
    --project="$PROJECT_ID" \
    --filter="labels.managed-by=terraform OR labels.purpose=dr-cold-standby" \
    --limit=5 \
    --format="table(name,diskSizeGb,status,creationTimestamp)" 2>/dev/null)

if [ -n "$SNAPSHOTS" ]; then
    echo "$SNAPSHOTS"
    log_success "Snapshot policy is configured"
else
    log_info "No snapshots yet (will be created based on schedule)"
fi
echo ""

# Check Heartbeat Instance
log_info "Checking Heartbeat Instance..."
HEARTBEAT_NAME=$(terraform output -raw heartbeat_instance_name 2>/dev/null)
HEARTBEAT_STATUS=$(gcloud compute instances describe "$HEARTBEAT_NAME" \
    --zone="${PRIMARY_REGION}-a" \
    --project="$PROJECT_ID" \
    --format="value(status)" 2>/dev/null || echo "NOT_FOUND")

if [ "$HEARTBEAT_STATUS" = "RUNNING" ]; then
    log_success "Heartbeat instance: RUNNING"
else
    log_warning "Heartbeat instance: $HEARTBEAT_STATUS"
fi
echo ""

# Check Monitoring
log_info "Checking Monitoring..."
UPTIME_CHECKS=$(gcloud monitoring uptime-check-configs list \
    --project="$PROJECT_ID" \
    --format="value(displayName)" 2>/dev/null | head -3)

if [ -n "$UPTIME_CHECKS" ]; then
    log_success "Uptime checks configured"
    echo "$UPTIME_CHECKS" | while read check; do echo "  - $check"; done
else
    log_warning "No uptime checks found"
fi
echo ""

# Summary
echo "============================================================"
echo "   Verification Summary"
echo "============================================================"
echo ""
echo "  Load Balancer URL:  http://$LB_IP"
echo "  Health Check:       http://$LB_IP/health"
echo ""
echo "  Quick Tests:"
echo "    curl http://$LB_IP/health"
echo "    curl http://$LB_IP/"
echo "    curl http://$LB_IP/api/data"
echo ""
echo "  View Monitoring:    https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo ""
