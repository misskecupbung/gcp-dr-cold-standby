#!/bin/bash
# Setup script - enables APIs and creates terraform.tfvars

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
echo "  DR Cold Standby Lab - Setup"
echo "============================================================"
echo ""

log_info "Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not installed. Get it from https://cloud.google.com/sdk/docs/install"
    exit 1
fi
log_success "gcloud CLI found"

if ! command -v terraform &> /dev/null; then
    log_error "Terraform not installed. Get it from https://www.terraform.io/downloads"
    exit 1
fi
TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
log_success "Terraform $TERRAFORM_VERSION found"

if ! command -v jq &> /dev/null; then
    log_warning "jq not installed - some scripts may not work properly."
fi

log_info "Checking GCP authentication..."
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
if [ -z "$CURRENT_ACCOUNT" ]; then
    log_warning "Not authenticated - starting login flow..."
    gcloud auth login
    gcloud auth application-default login
else
    log_success "Authenticated as: $CURRENT_ACCOUNT"
fi

log_info "Checking GCP project..."
if [ -z "$GCP_PROJECT_ID" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$CURRENT_PROJECT" ]; then
        log_error "No project set. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    PROJECT_ID=$CURRENT_PROJECT
else
    PROJECT_ID=$GCP_PROJECT_ID
fi
log_success "Using project: $PROJECT_ID"

log_info "Enabling GCP APIs..."
APIS=(
    "compute.googleapis.com"
    "dns.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "iam.googleapis.com"
    "storage.googleapis.com"
    "oslogin.googleapis.com"
    "iap.googleapis.com"
)

for api in "${APIS[@]}"; do
    log_info "  Enabling $api..."
    gcloud services enable "$api" --project="$PROJECT_ID" --quiet
done
log_success "All required APIs enabled"

# Create terraform.tfvars if not exists
TFVARS_FILE="$PROJECT_ROOT/terraform/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    log_info "Creating terraform.tfvars from example..."
    cp "$PROJECT_ROOT/terraform/terraform.tfvars.example" "$TFVARS_FILE"
    
    # Get default email from gcloud
    DEFAULT_EMAIL=$(gcloud config get-value account 2>/dev/null)
    
    # Prompt for notification email
    echo ""
    read -p "Enter notification email [$DEFAULT_EMAIL]: " INPUT_EMAIL
    USER_EMAIL=${INPUT_EMAIL:-$DEFAULT_EMAIL}
    USER_NAME=$(echo "$USER_EMAIL" | cut -d'@' -f1)
    
    # Update values in tfvars
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/your-gcp-project-id/$PROJECT_ID/" "$TFVARS_FILE"
        sed -i '' "s/your-email@example.com/$USER_EMAIL/" "$TFVARS_FILE"
        sed -i '' "s/your-name/$USER_NAME/" "$TFVARS_FILE"
    else
        sed -i "s/your-gcp-project-id/$PROJECT_ID/" "$TFVARS_FILE"
        sed -i "s/your-email@example.com/$USER_EMAIL/" "$TFVARS_FILE"
        sed -i "s/your-name/$USER_NAME/" "$TFVARS_FILE"
    fi
    
    echo ""
    log_success "Created terraform.tfvars with values:"
    log_info "  project_id: $PROJECT_ID"
    log_info "  notification_email: $USER_EMAIL"
    log_info "  owner: $USER_NAME"
else
    log_info "terraform.tfvars already exists"
fi

# Initialize Terraform
log_info "Initializing Terraform..."
cd "$PROJECT_ROOT/terraform"
terraform init

log_success "Setup complete!"
echo ""
echo "============================================================"
echo "   Next Steps:"
echo "============================================================"
echo ""
echo "1. Review and update: terraform/terraform.tfvars"
echo "2. Run: ./scripts/deploy.sh"
echo ""
