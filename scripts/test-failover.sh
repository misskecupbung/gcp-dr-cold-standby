#!/bin/bash
# =============================================================================
# Test Failover Script - Automated DR Testing
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
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_step() { echo -e "${CYAN}[TEST]${NC} $1"; }
log_header() { echo -e "${MAGENTA}============================================================${NC}"; echo -e "${MAGENTA}   $1${NC}"; echo -e "${MAGENTA}============================================================${NC}"; }

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

record_test() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$1" = "pass" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "$2"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "$2"
    fi
}

# Banner
clear
log_header "GCP DR Cold Standby Lab - DR TEST"
echo ""

# Parse arguments
SIMULATE_FAILURE=false
FULL_TEST=false
REPORT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --simulate-failure)
            SIMULATE_FAILURE=true
            shift
            ;;
        --full)
            FULL_TEST=true
            shift
            ;;
        --report)
            REPORT_FILE=$2
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --simulate-failure  Simulate primary failure by scaling down"
            echo "  --full              Run full DR test including failback"
            echo "  --report FILE       Save test report to file"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get configuration
cd "$PROJECT_ROOT/terraform"

log_info "Loading configuration..."
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)
PRIMARY_MIG=$(terraform output -raw primary_mig_name 2>/dev/null)
STANDBY_MIG=$(terraform output -raw standby_mig_name 2>/dev/null)
DR_INFO=$(terraform output -json dr_recovery_info 2>/dev/null)
PRIMARY_REGION=$(echo "$DR_INFO" | jq -r '.primary_region')
STANDBY_REGION=$(echo "$DR_INFO" | jq -r '.standby_region')
LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null)

TEST_START=$(date +%s)
TEST_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo ""
log_header "Phase 1: Pre-Failover Validation"
echo ""

# Test 1: Verify primary region is running
log_step "Test 1: Primary region health check"

# Check if PRIMARY_MIG is set
if [ -z "$PRIMARY_MIG" ]; then
    record_test "fail" "Could not get PRIMARY_MIG from terraform output"
else
    # Use MIG describe to get current size
    MIG_INFO=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(targetSize)" 2>/dev/null || echo "0")
    PRIMARY_COUNT=$(echo "$MIG_INFO" | tr -d '\n' | tr -d ' ')
    PRIMARY_COUNT=${PRIMARY_COUNT:-0}

    if [ "$PRIMARY_COUNT" -ge 1 ]; then
        record_test "pass" "Primary region has $PRIMARY_COUNT running instances"
    else
        record_test "fail" "Primary region has no running instances"
    fi
fi

# Test 2: Verify load balancer is responding
log_step "Test 2: Load balancer health check"
LB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")

if [ "$LB_STATUS" = "200" ]; then
    record_test "pass" "Load balancer returning HTTP 200"
else
    record_test "fail" "Load balancer returned HTTP $LB_STATUS"
fi

# Test 3: Verify application response
log_step "Test 3: Application response validation"
APP_RESPONSE=$(curl -s "http://$LB_IP/" 2>/dev/null)
APP_REGION=$(echo "$APP_RESPONSE" | jq -r '.region' 2>/dev/null || echo "")

if [ -n "$APP_REGION" ]; then
    record_test "pass" "Application responding from region: $APP_REGION"
else
    record_test "fail" "Application not responding correctly"
fi

# Test 4: Verify standby is in cold state
log_step "Test 4: Standby region cold state verification"
STANDBY_INSTANCES=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
    --region="$STANDBY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" 2>/dev/null || echo "")
if [ -z "$STANDBY_INSTANCES" ]; then
    STANDBY_COUNT=0
else
    STANDBY_COUNT=$(echo "$STANDBY_INSTANCES" | grep -c . 2>/dev/null || echo "0")
fi
STANDBY_COUNT=$(echo "$STANDBY_COUNT" | tr -d '\n' | tr -d ' ')
STANDBY_COUNT=${STANDBY_COUNT:-0}

if [ "$STANDBY_COUNT" -eq 0 ]; then
    record_test "pass" "Standby region is in cold state (0 instances)"
else
    record_test "warn" "Standby region has $STANDBY_COUNT instances (expected 0)"
fi

# Test 5: Verify snapshot policy exists
log_step "Test 5: Snapshot policy validation"

# Check for snapshot schedule policy (more reliable than counting snapshots)
POLICY_COUNT=$(gcloud compute resource-policies list \
    --project="$PROJECT_ID" \
    --filter="name~dr" \
    --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')
POLICY_COUNT=${POLICY_COUNT:-0}

if [ "$POLICY_COUNT" -ge 1 ]; then
    record_test "pass" "Found $POLICY_COUNT snapshot policy configured"
else
    # Check for any snapshots as fallback
    SNAPSHOT_COUNT=$(gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')
    SNAPSHOT_COUNT=${SNAPSHOT_COUNT:-0}
    
    if [ "$SNAPSHOT_COUNT" -ge 1 ]; then
        record_test "pass" "Found $SNAPSHOT_COUNT snapshots in the project"
    else
        record_test "fail" "No snapshot policy or snapshots found"
    fi
fi

echo ""

# Simulate failure if requested
if [ "$SIMULATE_FAILURE" = true ]; then
    log_header "Phase 2: Simulated Primary Failure"
    echo ""
    
    log_warning "Simulating primary region failure..."
    FAILOVER_START=$(date +%s)
    
    # Disable autoscaling first (like failover.sh does)
    log_info "Disabling autoscaling..."
    gcloud compute instance-groups managed stop-autoscaling "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null || true
    gcloud compute instance-groups managed stop-autoscaling "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" 2>/dev/null || true
    
    # Scale down primary
    log_step "Scaling down primary region to simulate failure..."
    gcloud compute instance-groups managed resize "$PRIMARY_MIG" \
        --size=0 \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --quiet
    
    log_info "Waiting for primary to scale down..."
    # Wait for primary to actually stop (using isStable)
    MAX_WAIT=180
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        IS_STABLE=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
            --region="$PRIMARY_REGION" \
            --project="$PROJECT_ID" \
            --format="value(status.isStable)" 2>/dev/null || echo "False")
        TARGET=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
            --region="$PRIMARY_REGION" \
            --project="$PROJECT_ID" \
            --format="value(targetSize)" 2>/dev/null || echo "0")
        
        if [ "$IS_STABLE" = "True" ] && [ "$TARGET" = "0" ]; then
            break
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    # Verify primary is down
    log_step "Test 6: Verify primary failure simulation"
    PRIMARY_TARGET=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(targetSize)" 2>/dev/null || echo "0")
    
    if [ "$PRIMARY_TARGET" = "0" ]; then
        record_test "pass" "Primary region successfully stopped"
    else
        record_test "fail" "Primary region still has $PRIMARY_TARGET instances"
    fi
    
    echo ""
    log_header "Phase 3: Failover Execution"
    echo ""
    
    # Scale up standby
    log_step "Activating standby region..."
    gcloud compute instance-groups managed resize "$STANDBY_MIG" \
        --size=2 \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --quiet
    
    log_info "Waiting for standby instances to start..."
    
    # Wait for standby using isStable (like failover.sh)
    MAX_WAIT=300
    WAIT_INTERVAL=15
    ELAPSED=0
    STANDBY_COUNT=0
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        # Check if MIG is stable with target size
        MIG_STATUS=$(gcloud compute instance-groups managed describe "$STANDBY_MIG" \
            --region="$STANDBY_REGION" \
            --project="$PROJECT_ID" \
            --format="value(status.isStable,targetSize)" 2>/dev/null)
        IS_STABLE=$(echo "$MIG_STATUS" | cut -f1)
        TARGET_SIZE=$(echo "$MIG_STATUS" | cut -f2)
        
        if [ "$IS_STABLE" = "True" ] && [ "$TARGET_SIZE" = "2" ]; then
            STANDBY_COUNT=2
            break
        fi
        
        # Get current running count for display
        CURRENT=$(gcloud compute instance-groups managed describe "$STANDBY_MIG" \
            --region="$STANDBY_REGION" \
            --project="$PROJECT_ID" \
            --format="value(currentActions.none)" 2>/dev/null || echo "0")
        CURRENT=${CURRENT:-0}
        
        log_info "  ${CURRENT}/2 instances running... (${ELAPSED}s)"
        sleep $WAIT_INTERVAL
        ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    done
    
    FAILOVER_END=$(date +%s)
    RTO_ACTUAL=$((FAILOVER_END - FAILOVER_START))
    
    # Test 7: Verify standby activation
    log_step "Test 7: Standby region activation"
    if [ "$STANDBY_COUNT" -ge 2 ]; then
        record_test "pass" "Standby region activated with $STANDBY_COUNT instances"
    else
        record_test "fail" "Standby region only has $STANDBY_COUNT instances"
    fi
    
    # Switch URL map to standby backend (like failover.sh)
    log_info "Switching load balancer to standby region..."
    URL_MAP=$(gcloud compute url-maps list --project="$PROJECT_ID" --filter="name~dr-url-map" --format="value(name)" | head -1)
    
    if [ -n "$URL_MAP" ]; then
        TEMP_FILE="/tmp/url-map-test-failover-$$.yaml"
        gcloud compute url-maps export "$URL_MAP" --global --project="$PROJECT_ID" --destination="$TEMP_FILE" 2>/dev/null
        sed -i 's/dr-backend-primary/dr-backend-standby/g' "$TEMP_FILE"
        gcloud compute url-maps import "$URL_MAP" --global --project="$PROJECT_ID" --source="$TEMP_FILE" --quiet 2>/dev/null
        rm -f "$TEMP_FILE"
        log_success "Load balancer switched to standby"
    fi
    
    # Test 8: Verify RTO
    log_step "Test 8: RTO validation (target: 900s)"
    if [ "$RTO_ACTUAL" -le 900 ]; then
        record_test "pass" "RTO achieved: ${RTO_ACTUAL}s (target: 900s)"
    else
        record_test "fail" "RTO exceeded: ${RTO_ACTUAL}s (target: 900s)"
    fi
    
    # Wait for load balancer
    log_info "Waiting 60 seconds for load balancer health checks..."
    sleep 60
    
    # Test 9: Service availability after failover
    log_step "Test 9: Service availability after failover"
    POST_FAILOVER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")
    
    if [ "$POST_FAILOVER_STATUS" = "200" ]; then
        record_test "pass" "Service available after failover (HTTP $POST_FAILOVER_STATUS)"
    else
        record_test "fail" "Service unavailable after failover (HTTP $POST_FAILOVER_STATUS)"
    fi
    
    # Test 10: Verify traffic routing to standby
    log_step "Test 10: Traffic routing to standby region"
    POST_RESPONSE=$(curl -s "http://$LB_IP/" 2>/dev/null)
    POST_REGION=$(echo "$POST_RESPONSE" | jq -r '.region' 2>/dev/null || echo "")
    
    if [ "$POST_REGION" = "$STANDBY_REGION" ]; then
        record_test "pass" "Traffic routing to standby region: $POST_REGION"
    else
        record_test "warn" "Traffic region: $POST_REGION (expected: $STANDBY_REGION)"
    fi
    
    echo ""
    
    if [ "$FULL_TEST" = true ]; then
        log_header "Phase 4: Failback Test"
        echo ""
        
        log_step "Executing failback to primary region..."
        FAILBACK_START=$(date +%s)
        
        # Scale up primary
        gcloud compute instance-groups managed resize "$PRIMARY_MIG" \
            --size=2 \
            --region="$PRIMARY_REGION" \
            --project="$PROJECT_ID" \
            --quiet
        
        log_info "Waiting for primary instances..."
        
        ELAPSED=0
        PRIMARY_COUNT=0
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            # Check if MIG is stable with target size
            MIG_STATUS=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
                --region="$PRIMARY_REGION" \
                --project="$PROJECT_ID" \
                --format="value(status.isStable,targetSize)" 2>/dev/null)
            IS_STABLE=$(echo "$MIG_STATUS" | cut -f1)
            TARGET_SIZE=$(echo "$MIG_STATUS" | cut -f2)
            
            if [ "$IS_STABLE" = "True" ] && [ "$TARGET_SIZE" = "2" ]; then
                PRIMARY_COUNT=2
                break
            fi
            
            # Get current running count for display
            CURRENT=$(gcloud compute instance-groups managed describe "$PRIMARY_MIG" \
                --region="$PRIMARY_REGION" \
                --project="$PROJECT_ID" \
                --format="value(currentActions.none)" 2>/dev/null || echo "0")
            CURRENT=${CURRENT:-0}
            
            log_info "  ${CURRENT}/2 instances running... (${ELAPSED}s)"
            sleep $WAIT_INTERVAL
            ELAPSED=$((ELAPSED + WAIT_INTERVAL))
        done
        
        # Scale down standby
        gcloud compute instance-groups managed resize "$STANDBY_MIG" \
            --size=0 \
            --region="$STANDBY_REGION" \
            --project="$PROJECT_ID" \
            --quiet
        
        # Switch URL map back to primary backend
        log_info "Switching load balancer back to primary region..."
        URL_MAP=$(gcloud compute url-maps list --project="$PROJECT_ID" --filter="name~dr-url-map" --format="value(name)" | head -1)
        
        if [ -n "$URL_MAP" ]; then
            TEMP_FILE="/tmp/url-map-test-failback-$$.yaml"
            gcloud compute url-maps export "$URL_MAP" --global --project="$PROJECT_ID" --destination="$TEMP_FILE" 2>/dev/null
            sed -i 's/dr-backend-standby/dr-backend-primary/g' "$TEMP_FILE"
            gcloud compute url-maps import "$URL_MAP" --global --project="$PROJECT_ID" --source="$TEMP_FILE" --quiet 2>/dev/null
            rm -f "$TEMP_FILE"
            log_success "Load balancer switched back to primary"
        fi
        
        FAILBACK_END=$(date +%s)
        FAILBACK_DURATION=$((FAILBACK_END - FAILBACK_START))
        
        # Test 11: Failback success
        log_step "Test 11: Failback completion"
        if [ "$PRIMARY_COUNT" -ge 2 ]; then
            record_test "pass" "Failback completed in ${FAILBACK_DURATION}s"
        else
            record_test "fail" "Failback incomplete - only $PRIMARY_COUNT instances"
        fi
        
        sleep 60  # Wait for LB
        
        # Test 12: Post-failback service availability
        log_step "Test 12: Post-failback service availability"
        FINAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")
        
        if [ "$FINAL_STATUS" = "200" ]; then
            record_test "pass" "Service available after failback"
        else
            record_test "fail" "Service unavailable after failback (HTTP $FINAL_STATUS)"
        fi
    else
        # Restore original state
        log_header "Phase 4: Restore Original State"
        echo ""
        
        log_step "Restoring primary region..."
        gcloud compute instance-groups managed resize "$PRIMARY_MIG" \
            --size=2 \
            --region="$PRIMARY_REGION" \
            --project="$PROJECT_ID" \
            --quiet
        
        log_step "Scaling down standby region..."
        gcloud compute instance-groups managed resize "$STANDBY_MIG" \
            --size=0 \
            --region="$STANDBY_REGION" \
            --project="$PROJECT_ID" \
            --quiet
        
        log_success "Original state restored"
    fi
fi

# Calculate test duration
TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))

echo ""
log_header "DR Test Report"
echo ""
echo "  Test Started:     $TEST_TIMESTAMP"
echo "  Test Duration:    ${TEST_DURATION} seconds"
echo "  Tests Passed:     $TESTS_PASSED"
echo "  Tests Failed:     $TESTS_FAILED"
echo "  Total Tests:      $TESTS_TOTAL"
# Calculate percentage without bc (integer math)
if [ "$TESTS_TOTAL" -gt 0 ]; then
    SUCCESS_RATE=$((TESTS_PASSED * 100 / TESTS_TOTAL))
else
    SUCCESS_RATE=0
fi
echo "  Success Rate:     ${SUCCESS_RATE}%"
echo ""

if [ "$SIMULATE_FAILURE" = true ]; then
    echo "  Actual RTO:       ${RTO_ACTUAL:-N/A} seconds"
    echo "  Target RTO:       900 seconds (15 minutes)"
fi

echo ""

# Generate report file if requested
if [ -n "$REPORT_FILE" ]; then
    cat > "$REPORT_FILE" << EOF
# DR Test Report
Date: $TEST_TIMESTAMP
Project: $PROJECT_ID

## Summary
- Tests Passed: $TESTS_PASSED
- Tests Failed: $TESTS_FAILED
- Total Tests: $TESTS_TOTAL
- Success Rate: ${SUCCESS_RATE}%
- Test Duration: ${TEST_DURATION}s

## Recovery Metrics
- Actual RTO: ${RTO_ACTUAL:-N/A}s
- Target RTO: 900s

## Regions
- Primary: $PRIMARY_REGION
- Standby: $STANDBY_REGION

## Configuration
- Primary MIG: $PRIMARY_MIG
- Standby MIG: $STANDBY_MIG
- Load Balancer IP: $LB_IP
EOF
    log_success "Report saved to: $REPORT_FILE"
fi

# Exit with appropriate code
if [ "$TESTS_FAILED" -gt 0 ]; then
    log_error "DR test completed with failures"
    exit 1
else
    log_success "DR test completed successfully!"
    exit 0
fi
