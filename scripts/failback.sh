#!/bin/bash
# =============================================================================
# Failback Script - Return to Primary Region
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
echo "   GCP DR Cold Standby Lab - FAILBACK"
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
PRIMARY_SIZE=2
GRADUAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve|-y)
            AUTO_APPROVE=true
            shift
            ;;
        --size)
            PRIMARY_SIZE=$2
            shift 2
            ;;
        --gradual)
            GRADUAL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-approve  Skip confirmation prompt"
            echo "  --size N        Number of instances in primary (default: 2)"
            echo "  --gradual       Gradual failback (keep standby running during transition)"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check current status
PRIMARY_COUNT=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')

STANDBY_COUNT=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
    --region="$STANDBY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')

log_info "Current status:"
echo "  Primary instances:  $PRIMARY_COUNT"
echo "  Standby instances:  $STANDBY_COUNT"
echo ""

# Confirm failback
log_warning "This will FAILBACK to the primary region!"
if [ "$GRADUAL" = true ]; then
    log_info "Gradual mode: Standby will remain active until primary is healthy"
else
    log_warning "Direct mode: Standby will be scaled down immediately after primary is up"
fi
echo ""

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Do you want to proceed with failback? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_warning "Failback cancelled"
        exit 0
    fi
fi

FAILBACK_START=$(date +%s)
echo ""
log_info "Starting failback at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
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

# Step 1: Scale up primary region
log_step "Step 1: Scaling up primary region to $PRIMARY_SIZE instances..."
gcloud compute instance-groups managed resize "$PRIMARY_MIG" \
    --size="$PRIMARY_SIZE" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --quiet
log_success "Primary region scale-up initiated"

# Step 2: Wait for primary instances to be healthy
log_step "Step 2: Waiting for primary instances to become healthy..."
MAX_WAIT=600
WAIT_INTERVAL=15
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get running count from MIG status
    MIG_STATUS=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(status.isStable,targetSize)" 2>/dev/null)
    IS_STABLE=$(echo "$MIG_STATUS" | cut -f1)
    TARGET_SIZE=$(echo "$MIG_STATUS" | cut -f2)
    
    # Check if stable (all instances running)
    if [ "$IS_STABLE" = "True" ] && [ "$TARGET_SIZE" = "$PRIMARY_SIZE" ]; then
        HEALTHY_COUNT=$PRIMARY_SIZE
        log_success "All $PRIMARY_SIZE instances are running!"
        break
    fi
    
    # Get actual running count by listing instances
    HEALTHY_COUNT=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null | grep -c "RUNNING" || echo 0)
    
    if [ "$HEALTHY_COUNT" -ge "$PRIMARY_SIZE" ]; then
        log_success "All $PRIMARY_SIZE instances are running!"
        break
    fi
    
    log_info "  $HEALTHY_COUNT/$PRIMARY_SIZE instances running... (${ELAPSED}s elapsed)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    log_error "Timeout waiting for primary instances!"
    log_info "Checking final status..."
    gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID"
    log_warning "Keeping standby region active for safety"
    exit 1
fi

# Step 3: Switch URL map back to primary backend
log_step "Step 3: Switching load balancer to primary region..."

# Get URL map name
URL_MAP=$(gcloud compute url-maps list --project="$PROJECT_ID" --filter="name~dr-url-map" --format="value(name)" | head -1)

if [ -n "$URL_MAP" ]; then
    log_info "  URL Map: $URL_MAP"
    
    # Export, modify, and import URL map (handles path_matcher routing)
    TEMP_FILE="/tmp/url-map-failback-$$.yaml"
    gcloud compute url-maps export "$URL_MAP" --global --project="$PROJECT_ID" --destination="$TEMP_FILE" 2>/dev/null
    
    # Replace all standby backend references with primary
    sed -i 's/dr-backend-standby/dr-backend-primary/g' "$TEMP_FILE"
    
    # Import the modified URL map
    gcloud compute url-maps import "$URL_MAP" --global --project="$PROJECT_ID" --source="$TEMP_FILE" --quiet 2>/dev/null
    
    rm -f "$TEMP_FILE"
    log_success "Load balancer now pointing to primary region!"
else
    log_error "Could not find URL map"
fi

# Step 4: Verify primary is serving traffic
log_step "Step 4: Verifying primary region is healthy..."
sleep 30  # Give LB time to detect healthy backends

# Test the application
for i in {1..5}; do
    RESPONSE=$(curl -s "http://$LB_IP/" 2>/dev/null || echo "{}")
    REGION=$(echo "$RESPONSE" | jq -r '.region' 2>/dev/null || echo "unknown")
    log_info "  Request $i - Response from: $REGION"
    sleep 2
done

# Step 5: Scale down standby region
if [ "$GRADUAL" = true ]; then
    log_step "Step 5 (Gradual): Scaling down standby region gradually..."
    
    CURRENT_STANDBY=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')
    
    while [ "$CURRENT_STANDBY" -gt 0 ]; do
        NEW_SIZE=$((CURRENT_STANDBY - 1))
        log_info "  Scaling standby from $CURRENT_STANDBY to $NEW_SIZE..."
        
        gcloud compute instance-groups managed resize "$STANDBY_MIG" \
            --size="$NEW_SIZE" \
            --region="$STANDBY_REGION" \
            --project="$PROJECT_ID" \
            --quiet
        
        sleep 30  # Wait between scale-downs
        CURRENT_STANDBY=$NEW_SIZE
    done
    log_success "Standby region fully scaled down"
else
    log_step "Step 5: Scaling down standby region..."
    gcloud compute instance-groups managed resize "$STANDBY_MIG" \
        --size=0 \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --quiet
    log_success "Standby region scaled to 0 instances"
fi

# Step 6: Final verification
log_step "Step 6: Final verification..."
sleep 10

LB_TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")
FINAL_RESPONSE=$(curl -s "http://$LB_IP/" 2>/dev/null || echo "{}")
ACTIVE_REGION=$(echo "$FINAL_RESPONSE" | jq -r '.region' 2>/dev/null || echo "unknown")

# Calculate failback time
FAILBACK_END=$(date +%s)
FAILBACK_DURATION=$((FAILBACK_END - FAILBACK_START))

echo ""
echo "============================================================"
echo "   FAILBACK COMPLETE"
echo "============================================================"
echo ""
echo "  Failback Duration: ${FAILBACK_DURATION} seconds"
echo "  Active Region:     $PRIMARY_REGION"
echo "  Active Instances:  $PRIMARY_SIZE"
echo "  Load Balancer:     http://$LB_IP"
echo "  Health Status:     $LB_TEST_RESULT"
echo ""
log_success "Primary region is now serving traffic!"
echo ""
