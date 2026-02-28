# =============================================================================
# Terraform Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Load Balancer Outputs
# -----------------------------------------------------------------------------
output "load_balancer_ip" {
  description = "Global Load Balancer IP address"
  value       = module.load_balancing.lb_ip_address
}

output "load_balancer_url" {
  description = "URL to access the application"
  value       = "http://${module.load_balancing.lb_ip_address}"
}

# -----------------------------------------------------------------------------
# DNS Outputs
# -----------------------------------------------------------------------------
output "dns_zone_name" {
  description = "Cloud DNS managed zone name"
  value       = module.dns.zone_name
}

output "dns_name_servers" {
  description = "DNS name servers for the zone"
  value       = module.dns.name_servers
}

output "application_url" {
  description = "Application URL using domain name"
  value       = "http://${trimsuffix(var.domain_name, ".")}"
}

# -----------------------------------------------------------------------------
# Compute Outputs - Primary Region
# -----------------------------------------------------------------------------
output "primary_mig_name" {
  description = "Primary region Managed Instance Group name"
  value       = module.compute_primary.mig_name
}

output "primary_mig_self_link" {
  description = "Primary region MIG self link"
  value       = module.compute_primary.mig_id
}

output "primary_instance_template" {
  description = "Primary region instance template name"
  value       = module.compute_primary.instance_template_name
}

# -----------------------------------------------------------------------------
# Compute Outputs - Standby Region
# -----------------------------------------------------------------------------
output "standby_mig_name" {
  description = "Standby region Managed Instance Group name"
  value       = module.compute_standby.mig_name
}

output "standby_mig_self_link" {
  description = "Standby region MIG self link"
  value       = module.compute_standby.mig_id
}

output "standby_instance_template" {
  description = "Standby region instance template name"
  value       = module.compute_standby.instance_template_name
}

# -----------------------------------------------------------------------------
# Heartbeat Outputs
# -----------------------------------------------------------------------------
output "heartbeat_instance_name" {
  description = "Heartbeat monitoring instance name"
  value       = module.heartbeat.instance_name
}

output "heartbeat_instance_ip" {
  description = "Heartbeat instance internal IP"
  value       = module.heartbeat.instance_internal_ip
}

# -----------------------------------------------------------------------------
# Networking Outputs
# -----------------------------------------------------------------------------
output "network_name" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "primary_subnet_name" {
  description = "Primary region subnet name"
  value       = module.networking.primary_subnet_name
}

output "standby_subnet_name" {
  description = "Standby region subnet name"
  value       = module.networking.standby_subnet_name
}

# -----------------------------------------------------------------------------
# Snapshot Outputs
# -----------------------------------------------------------------------------
output "snapshot_policy_name" {
  description = "Snapshot schedule policy name"
  value       = module.snapshot.snapshot_policy_name
}

output "snapshot_policy_id" {
  description = "Snapshot schedule policy ID"
  value       = module.snapshot.snapshot_policy_id
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------
output "monitoring_dashboard_url" {
  description = "Cloud Monitoring dashboard URL"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}" : "Monitoring disabled"
}

# -----------------------------------------------------------------------------
# Helpful Commands
# -----------------------------------------------------------------------------
output "helpful_commands" {
  description = "Useful commands for managing the DR setup"
  value = {
    test_lb          = "curl -H 'Host: ${trimsuffix(var.domain_name, ".")}' http://${module.load_balancing.lb_ip_address}/health"
    check_primary    = "gcloud compute instance-groups managed list-instances ${module.compute_primary.mig_name} --region=${var.primary_region}"
    check_standby    = "gcloud compute instance-groups managed list-instances ${module.compute_standby.mig_name} --region=${var.standby_region}"
    scale_up_standby = "gcloud compute instance-groups managed resize ${module.compute_standby.mig_name} --size=2 --region=${var.standby_region}"
    list_snapshots   = "gcloud compute snapshots list --filter='labels.purpose=dr-cold-standby'"
    ssh_heartbeat    = "gcloud compute ssh ${module.heartbeat.instance_name} --zone=${var.primary_zone}"
  }
}

# -----------------------------------------------------------------------------
# DR Recovery Information
# -----------------------------------------------------------------------------
output "dr_recovery_info" {
  description = "Information needed for DR recovery"
  value = {
    primary_region      = var.primary_region
    standby_region      = var.standby_region
    snapshot_policy     = module.snapshot.snapshot_policy_name
    estimated_rpo       = "${var.snapshot_schedule_hours} hour(s)"
    estimated_rto       = "10-15 minutes"
    failover_command    = "./scripts/failover.sh"
    failback_command    = "./scripts/failback.sh"
  }
}
