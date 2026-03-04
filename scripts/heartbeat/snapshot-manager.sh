#!/bin/bash
# Snapshot manager - handles DR snapshot lifecycle

set -e

PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PROJECT_ID" -H "Metadata-Flavor: Google")
PRIMARY_MIG=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_MIG" -H "Metadata-Flavor: Google")
PRIMARY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/PRIMARY_REGION" -H "Metadata-Flavor: Google")
STANDBY_REGION=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/STANDBY_REGION" -H "Metadata-Flavor: Google")

SNAPSHOT_PREFIX="dr-snapshot"
RETENTION_DAYS=7
LOG_FILE="/var/log/heartbeat/snapshot.log"
STATE_FILE="/var/lib/heartbeat/snapshot_state.json"

mkdir -p /var/log/heartbeat
mkdir -p /var/lib/heartbeat

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
    echo "$(timestamp) - $1" >> "$LOG_FILE"
}

log_console() {
    echo "$(timestamp) - $1" | tee -a "$LOG_FILE"
}

get_primary_disks() {
    local instances
    instances=$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
        --region="$PRIMARY_REGION" \
        --project="$PROJECT_ID" \
        --format="value(instance)" 2>/dev/null)
    
    local disks=""
    for instance in $instances; do
        instance_name=$(basename "$instance")
        zone=$(gcloud compute instances describe "$instance_name" \
            --project="$PROJECT_ID" \
            --format="value(zone)" 2>/dev/null | rev | cut -d'/' -f1 | rev)
        
        instance_disks=$(gcloud compute instances describe "$instance_name" \
            --zone="$zone" \
            --project="$PROJECT_ID" \
            --format="value(disks[].source)" 2>/dev/null)
        
        for disk in $instance_disks; do
            disk_name=$(basename "$disk")
            disks="$disks $disk_name:$zone"
        done
    done
    
    echo "$disks"
}

create_snapshot() {
    local disk_name=$1
    local zone=$2
    local timestamp_suffix=$(date +%Y%m%d%H%M%S)
    local snapshot_name="${SNAPSHOT_PREFIX}-${disk_name}-${timestamp_suffix}"
    
    log "Creating snapshot: $snapshot_name for disk: $disk_name"
    
    gcloud compute snapshots create "$snapshot_name" \
        --source-disk="$disk_name" \
        --source-disk-zone="$zone" \
        --project="$PROJECT_ID" \
        --labels="purpose=dr-cold-standby,source_disk=$disk_name,source_zone=$zone,managed_by=snapshot-manager" \
        --storage-location="us" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "Successfully created snapshot: $snapshot_name"
        return 0
    else
        log "Failed to create snapshot: $snapshot_name"
        return 1
    fi
}

list_snapshots() {
    gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --filter="labels.purpose=dr-cold-standby OR labels.managed_by=snapshot-manager" \
        --format="table(name,diskSizeGb,status,creationTimestamp,labels.source_disk)" \
        2>/dev/null
}

cleanup_old_snapshots() {
    local cutoff_date
    cutoff_date=$(date -d "-${RETENTION_DAYS} days" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -v-${RETENTION_DAYS}d -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log "Cleaning up snapshots older than: $cutoff_date"
    
    old_snapshots=$(gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --filter="labels.managed_by=snapshot-manager AND creationTimestamp<'$cutoff_date'" \
        --format="value(name)" 2>/dev/null)
    
    for snapshot in $old_snapshots; do
        log "Deleting old snapshot: $snapshot"
        gcloud compute snapshots delete "$snapshot" \
            --project="$PROJECT_ID" \
            --quiet 2>/dev/null || log "Failed to delete: $snapshot"
    done
}

get_latest_snapshot() {
    local disk_name=$1
    
    gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --filter="labels.source_disk=$disk_name AND labels.managed_by=snapshot-manager" \
        --sort-by="~creationTimestamp" \
        --limit=1 \
        --format="value(name)" 2>/dev/null
}

check_policy_snapshots() {
    log "Checking policy-based snapshots..."
    
    policy_snapshots=$(gcloud compute snapshots list \
        --project="$PROJECT_ID" \
        --filter="labels.snapshot_policy:*" \
        --limit=10 \
        --format="table(name,status,creationTimestamp)" 2>/dev/null)
    
    if [ -n "$policy_snapshots" ]; then
        log "Recent policy-based snapshots found"
        echo "$policy_snapshots"
    else
        log "No policy-based snapshots found"
    fi
}

main() {
    local action=${1:-"status"}}
    
    case "$action" in
        create)
            log_console "Creating snapshots for all primary disks..."
            disks=$(get_primary_disks)
            
            for disk_info in $disks; do
                disk_name=$(echo "$disk_info" | cut -d':' -f1)
                zone=$(echo "$disk_info" | cut -d':' -f2)
                create_snapshot "$disk_name" "$zone"
            done
            ;;
        
        list)
            log_console "Listing all DR snapshots..."
            list_snapshots
            ;;
        
        cleanup)
            log_console "Cleaning up old snapshots..."
            cleanup_old_snapshots
            ;;
        
        status)
            log_console "Snapshot Manager Status"
            echo ""
            echo "Project: $PROJECT_ID"
            echo "Primary MIG: $PRIMARY_MIG"
            echo "Retention: $RETENTION_DAYS days"
            echo ""
            echo "Recent Snapshots:"
            list_snapshots | head -10
            echo ""
            check_policy_snapshots
            ;;
        
        *)
            echo "Usage: $0 {create|list|cleanup|status}"
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
