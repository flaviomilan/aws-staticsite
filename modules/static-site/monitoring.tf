# --------------------------------------------------------------
# SNS Topic for Alarm Notifications
# --------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  name = "${replace(var.domain, ".", "-")}-alarms"
  tags = local.project_tags
}

resource "aws_sns_topic_subscription" "email" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --------------------------------------------------------------
# CloudFront 5xx Error Rate Alarm
# --------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain}-cloudfront-5xx-errors"
  alarm_description   = "CloudFront 5xx error rate exceeds 5% for ${var.domain}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.s3_distribution[0].id
    Region         = "Global"
  }

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions    = var.notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = local.project_tags
}

# --------------------------------------------------------------
# CloudFront 4xx Error Rate Alarm
# --------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.domain}-cloudfront-4xx-errors"
  alarm_description   = "CloudFront 4xx error rate exceeds 15% for ${var.domain}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 15
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.s3_distribution[0].id
    Region         = "Global"
  }

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = local.project_tags
}

# --------------------------------------------------------------
# WAF Blocked Requests Alarm
# --------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring && var.enable_waf ? 1 : 0

  alarm_name          = "${var.domain}-waf-blocked-spike"
  alarm_description   = "WAF blocked requests spike detected for ${var.domain}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.waf[0].visibility_config[0].metric_name
    Rule   = "ALL"
  }

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []

  tags = local.project_tags
}

# --------------------------------------------------------------
# CloudWatch Dashboard
# --------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_monitoring ? 1 : 0

  dashboard_name = replace("${var.domain}-dashboard", ".", "-")

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title = "CloudFront Requests"
            metrics = [
              ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Sum" }]
            ]
            period = 300
            region = "us-east-1"
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title = "CloudFront Error Rates"
            metrics = [
              ["AWS/CloudFront", "4xxErrorRate", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Average", color = "#ff9900" }],
              ["AWS/CloudFront", "5xxErrorRate", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Average", color = "#d13212" }]
            ]
            period = 300
            region = "us-east-1"
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title = "CloudFront Bytes Transferred"
            metrics = [
              ["AWS/CloudFront", "BytesDownloaded", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Sum", label = "Downloaded" }],
              ["AWS/CloudFront", "BytesUploaded", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Sum", label = "Uploaded" }]
            ]
            period = 300
            region = "us-east-1"
          }
        }
      ],
      var.enable_additional_metrics ? [
        {
          type   = "metric"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            title = "CloudFront Cache Hit Rate"
            metrics = [
              ["AWS/CloudFront", "CacheHitRate", "DistributionId", aws_cloudfront_distribution.s3_distribution[0].id, "Region", "Global", { stat = "Average" }]
            ]
            period = 300
            region = "us-east-1"
          }
        }
      ] : [],
      var.enable_waf ? [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title = "WAF Allowed vs Blocked"
            metrics = [
              ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.waf[0].visibility_config[0].metric_name, "Rule", "ALL", { stat = "Sum", color = "#2ca02c" }],
              ["AWS/WAFV2", "BlockedRequests", "WebACL", aws_wafv2_web_acl.waf[0].visibility_config[0].metric_name, "Rule", "ALL", { stat = "Sum", color = "#d13212" }]
            ]
            period = 300
            region = "us-east-1"
          }
        }
      ] : []
    )
  })
}
