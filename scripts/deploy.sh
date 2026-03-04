#!/bin/bash
# Deploy script - runs terraform to create the DR infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================================"
echo "  DR Cold Standby Lab - Deploy"
echo "============================================================"
echo ""

if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    log_error "terraform.tfvars not found. Run ./scripts/setup.sh first"
    exit 1
fi

PLAN_ONLY=false
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --plan)
            PLAN_ONLY=true
            shift
            ;;
        --auto-approve|-y)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --plan         Only run terraform plan, don't apply"
            echo "  --auto-approve Auto-approve terraform apply"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT/terraform"

log_info "Running terraform plan..."
terraform plan -out=tfplan

if [ "$PLAN_ONLY" = true ]; then
    log_success "Plan complete. Review the changes above."
    exit 0
fi

if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    read -p "Apply these changes? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_warning "Deployment cancelled"
        exit 0
    fi
fi

log_info "Applying terraform configuration..."
terraform apply tfplan

rm -f tfplan

echo ""
echo "============================================================"
echo "  Deployment Complete"
echo "============================================================"
echo ""
log_info "Resources:"
terraform output -json | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'

echo ""
log_success "Infrastructure deployed!"
echo ""
echo "============================================================"
echo "  Next Steps"
echo "============================================================"
echo ""
echo "1. Wait 3-5 minutes for instances to start and configure"
echo "2. Test the application:"
LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "PENDING")
echo "   curl http://$LB_IP/health"
echo ""
echo "3. To test failover:"
echo "   ./scripts/failover.sh"
echo ""
echo "4. View monitoring dashboard:"
echo "   https://console.cloud.google.com/monitoring/dashboards"
echo ""
