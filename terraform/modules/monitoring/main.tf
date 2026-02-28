# =============================================================================
# Monitoring Module - Cloud Monitoring and Alerting
# =============================================================================

# =============================================================================
# Notification Channel
# =============================================================================
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "DR Lab Email Notifications"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }
}

# =============================================================================
# Uptime Check - Load Balancer Health
# =============================================================================
resource "google_monitoring_uptime_check_config" "lb_health" {
  display_name = "DR Lab - Load Balancer Health"
  project      = var.project_id
  timeout      = "10s"
  period       = var.uptime_check_period

  http_check {
    path         = var.health_check_path
    port         = "80"
    use_ssl      = false
    validate_ssl = false

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.lb_ip_address
    }
  }

  content_matchers {
    content = "healthy"
    matcher = "CONTAINS_STRING"
  }
}

# =============================================================================
# Alert Policy - Primary Region Down
# =============================================================================
resource "google_monitoring_alert_policy" "primary_down" {
  display_name = "DR Lab - Primary Region Unhealthy"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Primary MIG Instance Count Low"

    condition_threshold {
      filter          = "resource.type = \"gce_instance_group_manager\" AND resource.labels.instance_group_manager_name = \"${var.primary_mig_name}\" AND metric.type = \"compute.googleapis.com/instance_group/size\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Primary region instance group has fewer than expected instances. Check if failover is needed."
    mime_type = "text/markdown"
  }
}

# =============================================================================
# Alert Policy - Uptime Check Failed
# =============================================================================
resource "google_monitoring_alert_policy" "uptime_failed" {
  display_name = "DR Lab - Service Unavailable"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Uptime Check Failed"

    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.host"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "The application uptime check has failed. Service may be unavailable. Initiate DR failover if primary region is confirmed down."
    mime_type = "text/markdown"
  }
}

# =============================================================================
# Alert Policy - High Latency
# =============================================================================
resource "google_monitoring_alert_policy" "high_latency" {
  display_name = "DR Lab - High Latency"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Load Balancer High Latency"

    condition_threshold {
      filter          = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/total_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5000  # 5 seconds

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Load balancer latency is high. Check backend health and consider scaling or failover."
    mime_type = "text/markdown"
  }
}

# =============================================================================
# Dashboard
# =============================================================================
resource "google_monitoring_dashboard" "dr_dashboard" {
  dashboard_json = jsonencode({
    displayName = "DR Cold Standby Dashboard"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Primary Region Instance Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"gce_instance_group_manager\" AND resource.labels.instance_group_manager_name = \"${var.primary_mig_name}\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Standby Region Instance Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"gce_instance_group_manager\" AND resource.labels.instance_group_manager_name = \"${var.standby_mig_name}\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Load Balancer Request Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/request_count\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Load Balancer Latency (p99)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/total_latencies\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_PERCENTILE_99"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Uptime Check Status"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_FRACTION_TRUE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Snapshot Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"gce_disk\" AND metric.type = \"compute.googleapis.com/storage/snapshot_count\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })

  project = var.project_id
}
