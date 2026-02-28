#!/bin/bash
# =============================================================================
# Failover Script - Activate Standby Region
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Banner
echo "============================================================"
echo "   GCP DR Cold Standby Lab - FAILOVER"
echo "============================================================"
echo ""

# Get configuration from Terraform
cd "$PROJECT_ROOT/terraform"

log_info "Loading configuration from Terraform state..."

PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)
PRIMARY_MIG=$(terraform output -raw primary_mig_name 2>/dev/null)
STANDBY_MIG=$(terraform output -raw standby_mig_name 2>/dev/null)
DR_INFO=$(terraform output -json dr_recovery_info 2>/dev/null)
PRIMARY_REGION=$(echo "$DR_INFO" | jq -r '.primary_region')
STANDBY_REGION=$(echo "$DR_INFO" | jq -r '.standby_region')
LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null)

log_info "Configuration loaded:"
echo "  Project:         $PROJECT_ID"
echo "  Primary MIG:     $PRIMARY_MIG ($PRIMARY_REGION)"
echo "  Standby MIG:     $STANDBY_MIG ($STANDBY_REGION)"
echo "  Load Balancer:   $LB_IP"
echo ""

# Parse arguments
AUTO_APPROVE=false
STANDBY_SIZE=2

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve|-y)
            AUTO_APPROVE=true
            shift
            ;;
        --size)
            STANDBY_SIZE=$2
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-approve  Skip confirmation prompt"
            echo "  --size N        Number of instances in standby (default: 2)"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Confirm failover
log_warning "This will initiate a FAILOVER to the standby region!"
log_warning "Primary region will be scaled down and standby will be activated."
echo ""

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Do you want to proceed with failover? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_warning "Failover cancelled"
        exit 0
    fi
fi

FAILOVER_START=$(date +%s)
echo ""
log_info "Starting failover at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Step 0: Disable autoscalers (required before manual resize)
log_step "Step 0: Disabling autoscalers for manual control..."

# Stop autoscaling on primary MIG
log_info "  Stopping autoscaling on primary MIG..."
gcloud compute instance-groups managed stop-autoscaling "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --quiet 2>/dev/null || log_warning "  Primary autoscaler not found or already stopped"

# Stop autoscaling on standby MIG
log_info "  Stopping autoscaling on standby MIG..."
gcloud compute instance-groups managed stop-autoscaling "$STANDBY_MIG" \
    --region="$STANDBY_REGION" \
    --project="$PROJECT_ID" \
    --quiet 2>/dev/null || log_warning "  Standby autoscaler not found or already stopped"

log_success "Autoscalers disabled"
echo ""

# Step 1: Create snapshot of primary disks (if possible)
log_step "Step 1: Creating emergency snapshot of primary region..."
PRIMARY_INSTANCES=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null || echo "")

if [ -n "$PRIMARY_INSTANCES" ]; then
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    for INSTANCE in $PRIMARY_INSTANCES; do
        INSTANCE_NAME=$(basename "$INSTANCE")
        log_info "  Creating snapshot for $INSTANCE_NAME..."
        
        # Get the data disk
        DISK_NAME="${INSTANCE_NAME}-data"
        ZONE=$(gcloud compute instances describe "$INSTANCE_NAME" \
            --project="$PROJECT_ID" \
            --format="value(zone)" 2>/dev/null | rev | cut -d'/' -f1 | rev)
        
        gcloud compute snapshots create "failover-${INSTANCE_NAME}-${TIMESTAMP}" \
            --source-disk="$INSTANCE_NAME" \
            --source-disk-zone="$ZONE" \
            --project="$PROJECT_ID" \
            --labels="purpose=dr-failover,timestamp=$TIMESTAMP" \
            --async 2>/dev/null || log_warning "  Could not create snapshot for $INSTANCE_NAME"
    done
    log_success "Emergency snapshots initiated"
else
    log_warning "No primary instances found or accessible"
fi

# Step 2: Scale down primary region
log_step "Step 2: Scaling down primary region..."
gcloud compute instance-groups managed resize "$PRIMARY_MIG" \
    --size=0 \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --quiet
log_success "Primary region scaled to 0 instances"

# Step 3: Scale up standby region
log_step "Step 3: Scaling up standby region to $STANDBY_SIZE instances..."
gcloud compute instance-groups managed resize "$STANDBY_MIG" \
    --size="$STANDBY_SIZE" \
    --region="$STANDBY_REGION" \
    --project="$PROJECT_ID" \
    --quiet
log_success "Standby region scale-up initiated"

# Step 4: Wait for standby instances to be healthy
log_step "Step 4: Waiting for standby instances to become healthy..."
MAX_WAIT=600
WAIT_INTERVAL=15
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get running count from MIG status
    MIG_STATUS=$(gcloud compute instance-groups managed describe "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(status.isStable,targetSize)" 2>/dev/null)
    IS_STABLE=$(echo "$MIG_STATUS" | cut -f1)
    TARGET_SIZE=$(echo "$MIG_STATUS" | cut -f2)
    
    # Check if stable (all instances running)
    if [ "$IS_STABLE" = "True" ] && [ "$TARGET_SIZE" = "$STANDBY_SIZE" ]; then
        HEALTHY_COUNT=$STANDBY_SIZE
        log_success "All $STANDBY_SIZE instances are running!"
        break
    fi
    
    # Get actual running count by listing instances
    HEALTHY_COUNT=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null | grep -c "RUNNING" || echo 0)
    
    if [ "$HEALTHY_COUNT" -ge "$STANDBY_SIZE" ]; then
        log_success "All $STANDBY_SIZE instances are running!"
        break
    fi
    
    log_info "  $HEALTHY_COUNT/$STANDBY_SIZE instances running... (${ELAPSED}s elapsed)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    log_warning "Timeout waiting for all instances. Current: $HEALTHY_COUNT/$STANDBY_SIZE"
    log_info "Checking final status..."
    gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID"
fi

# Step 5: Switch URL map to standby backend
log_step "Step 5: Switching load balancer to standby region..."

# Get URL map name
URL_MAP=$(gcloud compute url-maps list --project="$PROJECT_ID" --filter="name~dr-url-map" --format="value(name)" | head -1)

if [ -n "$URL_MAP" ]; then
    log_info "  URL Map: $URL_MAP"
    
    # Export, modify, and import URL map (handles path_matcher routing)
    TEMP_FILE="/tmp/url-map-failover-$$.yaml"
    gcloud compute url-maps export "$URL_MAP" --global --project="$PROJECT_ID" --destination="$TEMP_FILE" 2>/dev/null
    
    # Replace all primary backend references with standby
    sed -i 's/dr-backend-primary/dr-backend-standby/g' "$TEMP_FILE"
    
    # Import the modified URL map
    gcloud compute url-maps import "$URL_MAP" --global --project="$PROJECT_ID" --source="$TEMP_FILE" --quiet 2>/dev/null
    
    rm -f "$TEMP_FILE"
    log_success "Load balancer now pointing to standby region!"
else
    log_error "Could not find URL map"
fi

# Step 6: Verify load balancer health
log_step "Step 6: Verifying load balancer health..."
sleep 30  # Give LB time to detect healthy backends

LB_TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")
if [ "$LB_TEST_RESULT" = "200" ]; then
    log_success "Load balancer is serving traffic from standby region!"
else
    log_warning "Load balancer health check returned: $LB_TEST_RESULT (may need more time)"
fi

# Calculate failover time
FAILOVER_END=$(date +%s)
FAILOVER_DURATION=$((FAILOVER_END - FAILOVER_START))

echo ""
echo "============================================================"
echo "   FAILOVER COMPLETE"
echo "============================================================"
echo ""
echo "  Failover Duration: ${FAILOVER_DURATION} seconds"
echo "  Active Region:     $STANDBY_REGION"
echo "  Active Instances:  $HEALTHY_COUNT"
echo "  Load Balancer:     http://$LB_IP"
echo ""
log_info "Test the application:"
echo "  curl http://$LB_IP/health"
echo "  curl http://$LB_IP/"
echo ""
log_info "To failback to primary region, run:"
echo "  ./scripts/failback.sh"
echo ""
