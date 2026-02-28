#!/bin/bash
# =============================================================================
# Cleanup Script - Destroy All Resources
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Banner
echo "============================================================"
echo "   GCP DR Cold Standby Lab - Cleanup"
echo "============================================================"
echo ""
log_warning "This will destroy ALL resources created by this lab!"
echo ""

# Parse arguments
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve|-y)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-approve  Skip confirmation prompt"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Confirm before destroy
if [ "$AUTO_APPROVE" = false ]; then
    read -p "Are you SURE you want to destroy all resources? Type 'destroy' to confirm: " CONFIRM
    if [ "$CONFIRM" != "destroy" ]; then
        log_warning "Cleanup cancelled"
        exit 0
    fi
fi

cd "$PROJECT_ROOT/terraform"

# Check if state exists
if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
    log_warning "No Terraform state found. Nothing to destroy."
    exit 0
fi

# First, scale down standby to avoid errors
log_info "Scaling down instance groups..."
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)
STANDBY_MIG=$(terraform output -raw standby_mig_name 2>/dev/null || echo "")
STANDBY_REGION=$(terraform output -json dr_recovery_info 2>/dev/null | jq -r '.standby_region' || echo "us-east1")

if [ -n "$STANDBY_MIG" ]; then
    gcloud compute instance-groups managed resize "$STANDBY_MIG" \
        --size=0 \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --quiet 2>/dev/null || true
fi

# Destroy Terraform resources
log_info "Destroying Terraform resources..."
terraform destroy -auto-approve

# Clean up any remaining snapshots
log_info "Checking for remaining snapshots..."
SNAPSHOTS=$(gcloud compute snapshots list \
    --project="$PROJECT_ID" \
    --filter="labels.purpose=dr-lab" \
    --format="value(name)" 2>/dev/null || echo "")

if [ -n "$SNAPSHOTS" ]; then
    log_info "Deleting remaining snapshots..."
    for SNAPSHOT in $SNAPSHOTS; do
        gcloud compute snapshots delete "$SNAPSHOT" --project="$PROJECT_ID" --quiet 2>/dev/null || true
    done
fi

log_success "Cleanup complete!"
echo ""
echo "All resources have been destroyed."
echo ""
