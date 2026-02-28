# DR Cold Standby Architecture - Detailed Documentation

## Overview

This document provides in-depth technical details about the Cold Standby Disaster Recovery architecture implemented in this lab.

---

## Architecture Principles

### Cold Standby Definition

Cold Standby is a DR strategy where:

- **Primary Region**: Fully operational, handling all production traffic
- **Standby Region**: Infrastructure defined but not running (0 instances)
- **Failover**: Manual or semi-automated process to activate standby
- **Data Sync**: Periodic snapshots replicated to standby region

### Trade-offs

| Aspect | Cold Standby | Warm Standby | Hot Standby |
|--------|-------------|--------------|-------------|
| Cost | Low | Medium | High |
| RTO | 15-60 min | 5-15 min | < 5 min |
| RPO | 1-24 hours | Minutes | Seconds |
| Complexity | Low | Medium | High |

---

## Component Deep Dive

### 1. Global HTTP(S) Load Balancer

```
┌────────────────────────────────────────────────────────────────┐
│                   Global Load Balancer                         │
├────────────────────────────────────────────────────────────────┤
│  Forwarding Rule (Frontend)                                    │
│  └─► IP: 34.xxx.xxx.xxx:80                                     │
│                                                                │
│  Target HTTP Proxy                                             │
│  └─► URL Map                                                   │
│       └─► Default: Primary Backend Service                     │
│                                                                │
│  Backend Services                                              │
│  ├─► Primary (us-central1) - ACTIVE                            │
│  │    └─► MIG: dr-primary-mig                                  │
│  │                                                             │
│  └─► Standby (us-east1) - STANDBY                              │
│       └─► MIG: dr-standby-mig                                  │
│                                                                │
│  Health Check                                                  │
│  └─► HTTP /health:8080 (every 10s)                             │
└────────────────────────────────────────────────────────────────┘
```

**Key Configuration:**

```hcl
# Backend Service Configuration
resource "google_compute_backend_service" "primary" {
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  timeout_sec           = 30
  
  backend {
    group           = var.primary_mig_id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
  }
  
  connection_draining_timeout_sec = 300
}
```

### 2. Managed Instance Groups

#### Primary MIG

```
┌─────────────────────────────────────────────────────────────────┐
│                    Primary MIG (us-central1)                    │
├─────────────────────────────────────────────────────────────────┤
│  Instance Template: dr-primary-template                         │
│  ├─► Machine Type: n2-standard-2                                │
│  ├─► Boot Disk: 20GB pd-balanced                                │
│  ├─► Data Disk: 100GB pd-balanced                               │
│  └─► Startup Script: /app/startup-script.sh                     │
│                                                                 │
│  Autoscaling Policy                                             │
│  ├─► Min Instances: 2                                           │
│  ├─► Max Instances: 5                                           │
│  ├─► Target CPU: 70%                                            │
│  └─► Cool Down: 60s                                             │
│                                                                 │
│  Auto-Healing                                                   │
│  ├─► Health Check: dr-primary-health-check                      │
│  └─► Initial Delay: 300s                                        │
│                                                                 │
│  Update Policy                                                  │
│  ├─► Type: PROACTIVE                                            │
│  ├─► Max Surge: 3                                               │
│  └─► Max Unavailable: 0                                         │
└─────────────────────────────────────────────────────────────────┘
```

#### Standby MIG (Cold)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Standby MIG (us-east1)                       │
├─────────────────────────────────────────────────────────────────┤
│  Instance Template: dr-standby-template                         │
│  └─► (Same configuration as primary)                            │
│                                                                 │
│  Autoscaling Policy                                             │
│  ├─► Min Instances: 0 (COLD STANDBY)                            │
│  ├─► Max Instances: 5                                           │
│  └─► Target CPU: 70%                                            │
│                                                                 │
│  Status: No running instances                                   │
│  Ready to scale up on failover command                          │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Snapshot Schedule Policy

```
┌─────────────────────────────────────────────────────────────────┐
│                    Snapshot Schedule Policy                     │
├─────────────────────────────────────────────────────────────────┤
│  Name: dr-snapshot-policy                                       │
│                                                                 │
│  Schedule                                                       │
│  ├─► Frequency: Hourly                                          │
│  ├─► Hours in Cycle: 1                                          │
│  └─► Start Time: 00:00 UTC                                      │
│                                                                 │
│  Retention                                                      │
│  ├─► Max Retention Days: 7                                      │
│  └─► On Source Disk Delete: KEEP_AUTO_SNAPSHOTS                 │
│                                                                 │
│  Storage                                                        │
│  └─► Locations: ["us"] (multi-regional)                         │
│                                                                 │
│  Labels                                                         │
│  ├─► purpose: dr-cold-standby                                   │
│  └─► managed-by: terraform                                      │
└─────────────────────────────────────────────────────────────────┘
```

**Snapshot Timeline:**

```
Hour 0    Hour 1    Hour 2    Hour 3    Hour 4    ...   Hour 168 (7 days)
  │         │         │         │         │              │
  ▼         ▼         ▼         ▼         ▼              ▼
[Snap 1] [Snap 2] [Snap 3] [Snap 4] [Snap 5]  ...  [Snap 168]
                                                        │
                                                        ▼
                                               [Snap 1 deleted]
```

### 4. Heartbeat System

```
┌─────────────────────────────────────────────────────────────────┐
│                    Heartbeat Instance                           │
├─────────────────────────────────────────────────────────────────┤
│  Name: dr-heartbeat-xxxxxxxx                                    │
│  Machine Type: e2-small                                         │
│  Zone: us-central1-a                                            │
│                                                                 │
│  Monitoring Jobs (Cron)                                         │
│  ├─► */5 * * * * heartbeat.sh    # Every 5 minutes              │
│  └─► */15 * * * * snapshot-manager.sh  # Every 15 minutes       │
│                                                                 │
│  Functions                                                      │
│  ├─► Check primary MIG instance count                           │
│  ├─► Monitor instance health status                             │
│  ├─► Write custom metrics to Cloud Monitoring                   │
│  ├─► Verify snapshot creation                                   │
│  └─► Log health status                                          │
│                                                                 │
│  Failure Detection                                              │
│  ├─► Threshold: 3 consecutive failures                          │
│  └─► Action: Write critical metric, log alert                   │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPC: dr-vpc                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐   │
│  │  Subnet: primary        │  │  Subnet: standby            │   │
│  │  CIDR: 10.0.1.0/24      │  │  CIDR: 10.0.2.0/24          │   │
│  │  Region: us-central1    │  │  Region: us-east1           │   │
│  │                         │  │                             │   │
│  │  ┌─────────────────┐    │  │  ┌─────────────────┐        │   │
│  │  │ Primary VMs     │    │  │  │ Standby VMs     │        │   │
│  │  │ 10.0.1.2-254    │    │  │  │ (not running)   │        │   │
│  │  └─────────────────┘    │  │  └─────────────────┘        │   │
│  │                         │  │                             │   │
│  │  ┌─────────────────┐    │  │                             │   │
│  │  │ Heartbeat       │    │  │                             │   │
│  │  │ 10.0.1.X        │    │  │                             │   │
│  │  └─────────────────┘    │  │                             │   │
│  └─────────────────────────┘  └─────────────────────────────┘   │
│                                                                 │
│  Cloud NAT (both regions for outbound internet access)          │
│  Firewall Rules:                                                │
│  ├─► allow-internal: 10.0.0.0/16 → all ports                    │
│  ├─► allow-health-check: 35.191.0.0/16, 130.211.0.0/22 → 8080   │
│  ├─► allow-iap-ssh: 35.235.240.0/20 → 22                        │
│  └─► allow-http-https: 0.0.0.0/0 → 80, 443, 8080                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Failover Process

### Automated Detection

```
┌──────────────────────────────────────────────────────────────────┐
│                     Failure Detection Flow                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────────┐     │
│  │ LB Health   │───►│ Backend      │───►│ Alert Policy     │     │
│  │ Check       │    │ Unhealthy    │    │ Triggered        │     │
│  └─────────────┘    └──────────────┘    └────────┬─────────┘     │
│                                                   │              │
│                                                   ▼              │
│                                         ┌──────────────────┐     │
│                                         │ Notification     │     │
│                                         │ (Email/PagerDuty)│     │
│                                         └────────┬─────────┘     │
│                                                   │              │
│                                                   ▼              │
│                                         ┌──────────────────┐     │
│                                         │ Manual/Auto      │     │
│                                         │ Failover Trigger │     │
│                                         └──────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

### Failover Steps

```
Step 1: Create Emergency Snapshot (Optional)
├── Snapshot all primary data disks
└── Label with failover timestamp

Step 2: Scale Down Primary
├── Set primary MIG size to 0
└── Instances terminate gracefully

Step 3: Scale Up Standby
├── Set standby MIG size to N
├── New instances created from template
└── Instances run startup script

Step 4: Wait for Health
├── Instances register with LB
├── Health checks pass
└── Traffic begins routing

Step 5: Verify
├── Test application endpoints
├── Verify region in response
└── Monitor for errors
```

### Failover Timeline (Cold Standby)

```
Time    Action                                    Status
─────────────────────────────────────────────────────────────
T+0     Failure detected                          PRIMARY DOWN
T+1m    Alert triggered                           ALERTING
T+2m    Failover initiated                        FAILOVER
T+3m    Primary scaled to 0                       PRIMARY STOPPED
T+4m    Standby scale-up started                  STANDBY STARTING
T+8m    Instances running                         STANDBY RUNNING
T+10m   Health checks passing                     LB ROUTING
T+12m   Traffic fully switched                    STANDBY ACTIVE
─────────────────────────────────────────────────────────────
        Total RTO: ~12 minutes
```

---

## Recovery Point Objective (RPO)

### Data Loss Window

```
┌────────────────────────────────────────────────────────────────┐
│                    RPO Analysis                                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Snapshot Schedule: Every 1 hour                               │
│                                                                │
│  Best Case (failure right after snapshot):                     │
│  ├── Data Loss: ~0 minutes                                     │
│  └── Recovery from: Latest snapshot                            │
│                                                                │
│  Worst Case (failure right before snapshot):                   │
│  ├── Data Loss: ~60 minutes                                    │
│  └── Recovery from: Previous snapshot                          │
│                                                                │
│  Average RPO: 30 minutes                                       │
│                                                                │
│  Timeline:                                                     │
│                                                                │
│  Hour 0      Hour 1      Hour 2                                │
│    │           │           │                                   │
│    ▼           ▼           ▼                                   │
│  [Snap]     [Snap]     [Snap]                                  │
│    │           │           │                                   │
│    └─────┬─────┘           │                                   │
│          │                 │                                   │
│     FAILURE HERE = 59 min data loss                            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Improving RPO

Options to reduce RPO:

1. **More frequent snapshots** (every 15 min = ~7.5 min avg RPO)
2. **Database replication** (seconds RPO for DB)
3. **Application-level sync** (near-zero RPO)

---

## Security Considerations

### Service Accounts

```
┌─────────────────────────────────────────────────────────────────┐
│                    Service Account Permissions                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Compute Service Account (dr-primary-sa / dr-standby-sa)        │
│  ├── roles/logging.logWriter                                    │
│  ├── roles/monitoring.metricWriter                              │
│  ├── roles/compute.instanceAdmin.v1                             │
│  └── roles/storage.objectViewer                                 │
│                                                                 │
│  Heartbeat Service Account (dr-heartbeat-sa)                    │
│  ├── roles/compute.instanceAdmin.v1                             │
│  ├── roles/compute.storageAdmin (for snapshots)                 │
│  ├── roles/monitoring.metricWriter                              │
│  ├── roles/logging.logWriter                                    │
│  ├── roles/storage.objectAdmin                                  │
│  └── roles/dns.admin                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Network Security

- **No public IPs** on compute instances
- **IAP tunneling** for SSH access
- **Health check IPs** whitelisted only
- **Internal traffic** allowed within VPC
- **Shielded VMs** enabled
- **OS Login** enforced

---

## Best Practices

### DR Testing

1. **Regular Testing**: Monthly failover drills
2. **Documentation**: Keep runbooks updated
3. **Communication**: Practice team coordination
4. **Metrics**: Track actual RTO/RPO vs targets

### Monitoring

1. **Multiple signals**: Don't rely on single health check
2. **Alerting thresholds**: Balance noise vs. detection
3. **Dashboard visibility**: Clear status indicators
4. **Log retention**: Keep logs for post-incident analysis

### Operations

1. **Change management**: Test changes in non-prod first
2. **Capacity planning**: Ensure standby can handle load
3. **Data validation**: Verify snapshot integrity
4. **Documentation**: Maintain architecture diagrams
