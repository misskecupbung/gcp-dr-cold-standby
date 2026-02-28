# Troubleshooting Guide

Common issues and solutions for the GCP DR Cold Standby Lab.

---

## Table of Contents

1. [Deployment Issues](#deployment-issues)
2. [Load Balancer Issues](#load-balancer-issues)
3. [Instance Issues](#instance-issues)
4. [Failover Issues](#failover-issues)
5. [Monitoring Issues](#monitoring-issues)
6. [Network Issues](#network-issues)

---

## Deployment Issues

### Terraform Error: API Not Enabled

**Error:**
```
Error: Error creating Network: googleapi: Error 403: Compute Engine API has not been used in project...
```

**Solution:**
```bash
# Run setup script to enable APIs
./scripts/setup.sh

# Or manually enable
gcloud services enable compute.googleapis.com
```

### Terraform Error: Quota Exceeded

**Error:**
```
Error: Error creating Instance: googleapi: Error 403: Quota 'CPUS_ALL_REGIONS' exceeded
```

**Solution:**
1. Go to [IAM & Admin > Quotas](https://console.cloud.google.com/iam-admin/quotas)
2. Request quota increase for CPUs
3. Or reduce instance count in `terraform.tfvars`:
   ```hcl
   primary_min_replicas = 1
   primary_max_replicas = 2
   ```

### Terraform Error: Permission Denied

**Error:**
```
Error: Error creating ServiceAccount: googleapi: Error 403: Permission denied
```

**Solution:**
```bash
# Check your current permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID --filter="bindings.members:$(gcloud config get-value account)"

# Ensure you have Owner or Editor role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/owner"
```

---

## Load Balancer Issues

### 502 Bad Gateway Error

**Symptom:** Load balancer returns 502 errors

**Causes & Solutions:**

1. **Instances not ready yet**
   ```bash
   # Check instance status
   gcloud compute instance-groups managed list-instances \
     $(terraform output -raw primary_mig_name) \
     --region=us-central1
   
   # Wait 3-5 minutes for startup script to complete
   ```

2. **Health check failing**
   ```bash
   # Check health check status
   gcloud compute backend-services get-health dr-backend-primary-* --global
   
   # SSH to instance and check app
   gcloud compute ssh VM_NAME --zone=ZONE
   curl localhost:8080/health
   ```

3. **Firewall blocking health checks**
   ```bash
   # Verify firewall rules
   gcloud compute firewall-rules list --filter="name~dr-vpc"
   
   # Ensure health check IPs are allowed
   # 35.191.0.0/16 and 130.211.0.0/22
   ```

### 404 Not Found

**Symptom:** Load balancer returns 404

**Solution:**
```bash
# Check URL map configuration
gcloud compute url-maps describe dr-url-map-* --global

# Verify backend service
gcloud compute backend-services describe dr-backend-primary-* --global
```

### Connection Timeout

**Symptom:** `curl: (28) Connection timed out`

**Solutions:**
```bash
# Check if LB IP is correctly provisioned
terraform output load_balancer_ip

# Verify forwarding rule
gcloud compute forwarding-rules list --global

# Check instance network tags
gcloud compute instances describe VM_NAME --zone=ZONE --format="value(tags.items)"
```

---

## Instance Issues

### Instances Not Starting

**Symptom:** MIG shows 0 running instances

**Solutions:**

1. **Check instance group errors**
   ```bash
   gcloud compute instance-groups managed list-instances \
     $(terraform output -raw primary_mig_name) \
     --region=us-central1
   ```

2. **Check operations for errors**
   ```bash
   gcloud compute operations list \
     --filter="targetLink~instance-groups" \
     --sort-by="~insertTime" \
     --limit=10
   ```

3. **Check instance template**
   ```bash
   gcloud compute instance-templates describe \
     $(terraform output -raw primary_instance_template)
   ```

### Startup Script Failing

**Symptom:** Instance running but application not responding

**Solution:**
```bash
# SSH to instance
gcloud compute ssh VM_NAME --zone=ZONE

# Check startup script logs
sudo cat /var/log/startup-script.log

# Check application service
sudo systemctl status dr-app

# Check application logs
sudo journalctl -u dr-app -f
```

### Auto-Healing Constantly Replacing

**Symptom:** Instances keep getting recreated

**Solutions:**
```bash
# Check health check logs
gcloud logging read \
  "resource.type=gce_health_check" \
  --limit=50

# Verify application health endpoint
curl http://INSTANCE_IP:8080/health

# Check auto-healing configuration
gcloud compute instance-groups managed describe \
  $(terraform output -raw primary_mig_name) \
  --region=us-central1
```

---

## Failover Issues

### Failover Script Timeout

**Symptom:** `test-failover.sh` times out waiting for instances

**Solutions:**

1. **Increase wait time in script**
   ```bash
   # Edit scripts/failover.sh
   MAX_WAIT=600  # Increase from 300
   ```

2. **Check instance startup**
   ```bash
   # Watch instances
   watch -n 5 "gcloud compute instance-groups managed list-instances \
     $(terraform output -raw standby_mig_name) --region=us-east1"
   ```

3. **Check for quota issues**
   ```bash
   gcloud compute regions describe us-east1 --format="value(quotas)"
   ```

### Standby Not Receiving Traffic

**Symptom:** After failover, still getting traffic from primary

**Solutions:**

1. **Verify primary is down**
   ```bash
   gcloud compute instance-groups managed list-instances \
     $(terraform output -raw primary_mig_name) --region=us-central1
   ```

2. **Check backend health**
   ```bash
   gcloud compute backend-services get-health dr-backend-standby-* --global
   ```

3. **DNS propagation delay**
   ```bash
   # Check DNS records
   dig $(terraform output -json | jq -r '.domain_name.value') +short
   
   # Wait for TTL to expire (default 300s)
   ```

### Failback Not Working

**Symptom:** Primary not serving after failback

**Solutions:**
```bash
# Ensure primary instances are healthy
gcloud compute instance-groups managed list-instances \
  $(terraform output -raw primary_mig_name) \
  --region=us-central1 \
  --filter="status=RUNNING"

# Check load balancer backend health
gcloud compute backend-services get-health dr-backend-primary-* --global

# Force health check re-evaluation
gcloud compute health-checks update http dr-global-health-check-* \
  --check-interval=5s
```

---

## Monitoring Issues

### Uptime Check Failing

**Symptom:** Uptime check shows failures in Cloud Monitoring

**Solutions:**
```bash
# Check uptime check configuration
gcloud monitoring uptime-check-configs list

# Verify the monitored endpoint
curl -H "Host: dr-lab.example.com" http://$(terraform output -raw load_balancer_ip)/health

# Check for SSL issues (if HTTPS)
curl -k https://$(terraform output -raw load_balancer_ip)/health
```

### No Metrics in Dashboard

**Symptom:** Dashboard shows "No data"

**Solutions:**

1. **Wait for data collection** (5-10 minutes)

2. **Check monitoring agent**
   ```bash
   gcloud compute ssh VM_NAME --zone=ZONE
   sudo systemctl status google-cloud-ops-agent
   ```

3. **Verify metric filters**
   ```bash
   gcloud monitoring metrics list --filter="metric.type:compute.googleapis.com"
   ```

### Alerts Not Triggering

**Symptom:** Condition met but no alert

**Solutions:**
```bash
# Check alert policy
gcloud alpha monitoring policies list

# Verify notification channel
gcloud alpha monitoring channels list

# Check incident history
gcloud alpha monitoring incidents list
```

---

## Network Issues

### Cannot SSH to Instances

**Symptom:** `gcloud compute ssh` times out

**Solutions:**

1. **Use IAP tunneling** (recommended)
   ```bash
   gcloud compute ssh VM_NAME --zone=ZONE --tunnel-through-iap
   ```

2. **Check firewall rules**
   ```bash
   gcloud compute firewall-rules list --filter="name~iap"
   ```

3. **Enable IAP API**
   ```bash
   gcloud services enable iap.googleapis.com
   ```

### Instances Cannot Reach Internet

**Symptom:** apt-get or pip fails on instance

**Solutions:**
```bash
# Check NAT gateway
gcloud compute routers nats list --router=dr-vpc-router-primary --region=us-central1

# Verify routes
gcloud compute routes list --filter="network~dr-vpc"
```

### Cross-Region Communication Failing

**Symptom:** Primary cannot communicate with standby

**Solutions:**
```bash
# Check VPC network
gcloud compute networks describe dr-vpc

# Verify subnets
gcloud compute networks subnets list --filter="network~dr-vpc"

# Check firewall for internal traffic
gcloud compute firewall-rules describe dr-vpc-allow-internal
```

---

## Quick Diagnostic Commands

```bash
# Full infrastructure status
./scripts/verify-deployment.sh

# Check all instance groups
gcloud compute instance-groups managed list --filter="name~dr-"

# Check all health checks
gcloud compute health-checks list --filter="name~dr-"

# Check recent operations
gcloud compute operations list --sort-by="~insertTime" --limit=20

# Check project quotas
gcloud compute project-info describe --format="value(quotas)"

# Tail logs for debugging
gcloud logging read "resource.type=gce_instance AND jsonPayload.message:error" --limit=50
```

---

## Getting Help

If you're still stuck:

1. **Check GCP Status:** [status.cloud.google.com](https://status.cloud.google.com/)
2. **Review Logs:** Cloud Logging in Console
3. **Open Issue:** Create GitHub issue with:
   - Terraform version
   - Error message
   - Steps to reproduce
   - Output of `terraform output`
