# DR Operations Runbook

## Quick Reference

| Scenario | Command |
|----------|---------|
| Initiate Failover | `./scripts/failover.sh` |
| Failback to Primary | `./scripts/failback.sh` |
| Test DR | `./scripts/test-failover.sh --simulate-failure` |
| Check Status | `./scripts/verify-deployment.sh` |
| View Logs | `gcloud logging read "resource.type=gce_instance"` |

---

## 1. Failover Procedure

### When to Failover

Initiate failover when:
- Primary region is confirmed down (not just degraded)
- GCP Status indicates regional outage
- Multiple health checks failing for > 5 minutes
- Confirmed infrastructure failure (not application bug)

### Pre-Failover Checklist

- [ ] Confirm primary region failure (not application issue)
- [ ] Check GCP Status page
- [ ] Notify stakeholders
- [ ] Document timeline
- [ ] Have rollback plan ready

### Failover Steps

#### Step 1: Assess Situation (2 min)

```bash
# Check primary MIG status
gcloud compute instance-groups managed list-instances dr-primary-mig-* \
  --region=us-central1

# Check load balancer backend health
gcloud compute backend-services get-health dr-backend-primary-* --global

# Check GCP status
open https://status.cloud.google.com
```

#### Step 2: Create Emergency Snapshot (3 min)

```bash
# If primary instances are still accessible
./scripts/heartbeat/snapshot-manager.sh create
```

#### Step 3: Execute Failover (5-10 min)

```bash
# Run failover script
./scripts/failover.sh

# Or manually:
# Scale down primary
gcloud compute instance-groups managed resize dr-primary-mig-* \
  --size=0 --region=us-central1 --quiet

# Scale up standby
gcloud compute instance-groups managed resize dr-standby-mig-* \
  --size=2 --region=us-east1 --quiet
```

#### Step 4: Verify Failover (2 min)

```bash
# Check standby instances
gcloud compute instance-groups managed list-instances dr-standby-mig-* \
  --region=us-east1

# Test application
LB_IP=$(terraform -chdir=terraform output -raw load_balancer_ip)
curl http://$LB_IP/health
curl http://$LB_IP/

# Verify region in response
curl -s http://$LB_IP/ | jq '.region'
# Should show: "us-east1"
```

#### Step 5: Post-Failover Actions

- [ ] Update status page
- [ ] Notify stakeholders of successful failover
- [ ] Document failover time (RTO)
- [ ] Monitor for issues
- [ ] Plan failback when primary recovers

---

## 2. Failback Procedure

### When to Failback

Initiate failback when:
- Primary region is confirmed healthy
- Root cause identified and resolved
- During maintenance window (if possible)
- Team available to monitor

### Pre-Failback Checklist

- [ ] Primary region healthy in GCP Status
- [ ] Test deployment in primary region
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Have rollback plan ready

### Failback Steps

#### Step 1: Verify Primary Region Health (2 min)

```bash
# Check GCP region status
gcloud compute zones list --filter="region:us-central1"

# Test primary can start instances
gcloud compute instances create test-primary \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --no-address

# Clean up test instance
gcloud compute instances delete test-primary --zone=us-central1-a --quiet
```

#### Step 2: Execute Failback (5-10 min)

```bash
# Run failback script
./scripts/failback.sh

# Or use gradual failback
./scripts/failback.sh --gradual

# Manual steps:
# Scale up primary
gcloud compute instance-groups managed resize dr-primary-mig-* \
  --size=2 --region=us-central1 --quiet

# Wait for healthy
watch -n 5 "gcloud compute backend-services get-health dr-backend-primary-* --global"

# Scale down standby
gcloud compute instance-groups managed resize dr-standby-mig-* \
  --size=0 --region=us-east1 --quiet
```

#### Step 3: Verify Failback (2 min)

```bash
# Check traffic routing
for i in {1..5}; do
  curl -s http://$LB_IP/ | jq '.region'
  sleep 2
done
# Should show: "us-central1"
```

#### Step 4: Post-Failback Actions

- [ ] Update status page
- [ ] Notify stakeholders
- [ ] Conduct post-incident review
- [ ] Update documentation if needed

---

## 3. Monitoring Commands

### Instance Status

```bash
# List all DR instances
gcloud compute instances list --filter="name~dr-"

# Primary MIG status
gcloud compute instance-groups managed describe dr-primary-mig-* \
  --region=us-central1

# Standby MIG status  
gcloud compute instance-groups managed describe dr-standby-mig-* \
  --region=us-east1
```

### Health Checks

```bash
# Load balancer health
gcloud compute backend-services get-health dr-backend-primary-* --global
gcloud compute backend-services get-health dr-backend-standby-* --global

# Direct instance health check
curl http://INSTANCE_IP:8080/health
```

### Snapshots

```bash
# List recent snapshots
gcloud compute snapshots list \
  --filter="labels.purpose=dr-cold-standby" \
  --sort-by="~creationTimestamp" \
  --limit=10

# Check snapshot policy
gcloud compute resource-policies describe dr-snapshot-policy \
  --region=us-central1
```

### Logs

```bash
# Instance logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=INSTANCE_ID" \
  --limit=50

# Load balancer logs
gcloud logging read "resource.type=http_load_balancer" \
  --limit=50

# Application logs (on instance)
sudo journalctl -u dr-app -f
```

---

## 4. Troubleshooting Quick Reference

### Instances Not Starting

```bash
# Check operations
gcloud compute operations list \
  --filter="targetLink~instance-groups" \
  --sort-by="~insertTime" \
  --limit=5

# Check quotas
gcloud compute project-info describe --format="value(quotas)"
```

### Load Balancer 502 Errors

```bash
# Check backend health
gcloud compute backend-services get-health dr-backend-primary-* --global

# Check firewall rules
gcloud compute firewall-rules list --filter="name~dr-vpc"

# Test direct to instance
gcloud compute ssh INSTANCE_NAME --zone=ZONE -- curl localhost:8080/health
```

### Health Checks Failing

```bash
# Check health check config
gcloud compute health-checks describe dr-global-health-check-*

# Test endpoint
curl -v http://INSTANCE_IP:8080/health

# Check application service
gcloud compute ssh INSTANCE_NAME --zone=ZONE -- sudo systemctl status dr-app
```

---

## 5. Incident Response Checklist

### During Incident

- [ ] Acknowledge alert
- [ ] Assess impact and scope
- [ ] Notify stakeholders
- [ ] Execute failover if needed
- [ ] Document timeline
- [ ] Provide regular updates
- [ ] Verify recovery

### Post-Incident

- [ ] Document incident timeline
- [ ] Identify root cause
- [ ] Calculate actual RTO/RPO
- [ ] Update documentation
- [ ] Implement improvements
- [ ] Schedule post-incident review
- [ ] Update runbook if needed

---

## 6. Maintenance Procedures

### Scheduled Maintenance

```bash
# Perform rolling update (no downtime)
gcloud compute instance-groups managed rolling-action start-update dr-primary-mig-* \
  --version=template=NEW_TEMPLATE \
  --region=us-central1

# Check update status
gcloud compute instance-groups managed describe dr-primary-mig-* \
  --region=us-central1 \
  --format="value(status)"
```

### Testing DR (Quarterly)

```bash
# Run full DR test
./scripts/test-failover.sh --simulate-failure --full --report report.md

# Review results
cat report.md
```
