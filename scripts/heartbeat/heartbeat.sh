#!/bin/bash
# =============================================================================
# Heartbeat Monitoring Script
# Runs on the heartbeat instance to monitor primary region health
# =============================================================================

set -e

# Configuration from instance metadata
PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PROJECT_ID" -H "Metadata-Flavor: Google")
PRIMARY_MIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_MIG" -H "Metadata-Flavor: Google")
STANDBY_MIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/STANDBY_MIG" -H "Metadata-Flavor: Google")
PRIMARY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_REGION" -H "Metadata-Flavor: Google")
STANDBY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/STANDBY_REGION" -H "Metadata-Flavor: Google")

# Logging configuration
LOG_FILE="/var/log/heartbeat/heartbeat.log"
mkdir -p /var/log/heartbeat

# Functions
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
    echo "$(timestamp) - $1" >> "$LOG_FILE"
}

log_console() {
    echo "$(timestamp) - $1" | tee -a "$LOG_FILE"
}

# Health check function
check_primary_health() {
    local healthy_count
    healthy_count=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --filter="status=RUNNING" \
        --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')
    
    echo "$healthy_count"
}

# Check standby status
check_standby_status() {
    local standby_count
    standby_count=$(gcloud compute instance-groups managed list-instances "$STANDBY_MIG" \
        --region="$STANDBY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(instance)" 2>/dev/null | wc -l | tr -d ' ')
    
    echo "$standby_count"
}

# Write custom metric
write_metric() {
    local metric_name=$1
    local value=$2
    
    gcloud monitoring metrics write \
        --project="$PROJECT_ID" \
        "custom.googleapis.com/dr/$metric_name" \
        --value="$value" \
        --type=gauge \
        2>/dev/null || log "Failed to write metric: $metric_name"
}

# Main monitoring loop
main() {
    log_console "Starting heartbeat monitoring..."
    log_console "Project: $PROJECT_ID"
    log_console "Primary MIG: $PRIMARY_MIG ($PRIMARY_REGION)"
    log_console "Standby MIG: $STANDBY_MIG ($STANDBY_REGION)"
    
    # Failure threshold configuration
    FAILURE_THRESHOLD=3
    CONSECUTIVE_FAILURES=0
    
    while true; do
        # Check primary region health
        HEALTHY_COUNT=$(check_primary_health)
        STANDBY_COUNT=$(check_standby_status)
        
        log "Primary healthy instances: $HEALTHY_COUNT, Standby instances: $STANDBY_COUNT"
        
        # Write metrics
        write_metric "primary_healthy_instances" "$HEALTHY_COUNT"
        write_metric "standby_instances" "$STANDBY_COUNT"
        
        # Check for failures
        if [ "$HEALTHY_COUNT" -lt 1 ]; then
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            log "WARNING: Primary region unhealthy. Consecutive failures: $CONSECUTIVE_FAILURES/$FAILURE_THRESHOLD"
            
            write_metric "consecutive_failures" "$CONSECUTIVE_FAILURES"
            
            if [ "$CONSECUTIVE_FAILURES" -ge "$FAILURE_THRESHOLD" ]; then
                log "CRITICAL: Primary region failure threshold reached!"
                log "Automated failover should be triggered by alerting policies"
                
                # Reset counter to prevent spam
                CONSECUTIVE_FAILURES=0
            fi
        else
            if [ "$CONSECUTIVE_FAILURES" -gt 0 ]; then
                log "Primary region recovered. Resetting failure counter."
            fi
            CONSECUTIVE_FAILURES=0
            write_metric "consecutive_failures" "0"
        fi
        
        # Sleep before next check
        sleep 60
    done
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main
fi
