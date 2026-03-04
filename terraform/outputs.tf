# Outputs

output "load_balancer_ip" {
  description = "Global Load Balancer IP address"
  value       = module.load_balancing.lb_ip_address
}

output "load_balancer_url" {
  description = "URL to access the application"
  value       = "http://${module.load_balancing.lb_ip_address}"
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name"
  value       = var.enable_dns ? module.dns[0].zone_name : "DNS disabled"
}

output "dns_name_servers" {
  description = "DNS name servers for the zone"
  value       = var.enable_dns ? module.dns[0].name_servers : []
}

output "application_url" {
  description = "Application URL using domain name"
  value       = var.enable_dns ? "http://${trimsuffix(var.domain_name, ".")}" : "http://${module.load_balancing.lb_ip_address}"
}

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

output "heartbeat_primary_mig" {
  description = "Heartbeat primary MIG self link"
  value       = module.heartbeat.heartbeat_primary_mig
}

output "heartbeat_standby_mig" {
  description = "Heartbeat standby MIG self link"
  value       = module.heartbeat.heartbeat_standby_mig
}

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

output "snapshot_policy_name" {
  description = "Snapshot schedule policy name"
  value       = module.snapshot.snapshot_policy_name
}

output "snapshot_policy_id" {
  description = "Snapshot schedule policy ID"
  value       = module.snapshot.snapshot_policy_id
}

output "monitoring_dashboard_url" {
  description = "Cloud Monitoring dashboard URL"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}" : "Monitoring disabled"
}

output "helpful_commands" {
  description = "Useful commands for managing the DR setup"
  value = {
    test_lb          = "curl http://${module.load_balancing.lb_ip_address}/health"
    check_primary    = "gcloud compute instance-groups managed list-instances ${module.compute_primary.mig_name} --region=${var.primary_region}"
    check_standby    = "gcloud compute instance-groups managed list-instances ${module.compute_standby.mig_name} --region=${var.standby_region}"
    scale_up_standby = "gcloud compute instance-groups managed resize ${module.compute_standby.mig_name} --size=2 --region=${var.standby_region}"
    list_snapshots   = "gcloud compute snapshots list --filter='labels.purpose=dr-cold-standby'"
  }
}

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
