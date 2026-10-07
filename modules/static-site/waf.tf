# --------------------------------------------------------------
# WAF v2 Web ACL
# --------------------------------------------------------------

resource "aws_wafv2_web_acl" "waf" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_waf ? 1 : 0

  name  = "waf-${replace(var.domain, ".", "-")}"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting — prevent DDoS and brute-force attacks
  rule {
    name     = "RateLimitRule"
    priority = 0

    action {
      dynamic "count" {
        for_each = var.waf_mode == "count" ? [1] : []
        content {}
      }
      dynamic "block" {
        for_each = var.waf_mode == "block" ? [1] : []
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules — Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      dynamic "count" {
        for_each = var.waf_mode == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = var.waf_mode == "block" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules — Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      dynamic "count" {
        for_each = var.waf_mode == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = var.waf_mode == "block" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules — Amazon IP Reputation List
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      dynamic "count" {
        for_each = var.waf_mode == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = var.waf_mode == "block" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = var.block_anonymous_ips ? [1] : []
    content {
      name     = "AWSManagedRulesAnonymousIpList"
      priority = 4

      override_action {
        dynamic "count" {
          for_each = var.waf_mode == "count" ? [1] : []
          content {}
        }
        dynamic "none" {
          for_each = var.waf_mode == "block" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAnonymousIpList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "waf-anonymous-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = replace("waf-${var.bucket_name}", ".", "-")
    sampled_requests_enabled   = true
  }

  tags = local.project_tags
}

# --------------------------------------------------------------
# WAF Logging to CloudWatch
# --------------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf_logs" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_waf ? 1 : 0

  # WAF logging requires log group name to start with aws-waf-logs-
  name              = "aws-waf-logs-${replace(var.domain, ".", "-")}"
  retention_in_days = var.log_retention_days

  tags = local.project_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  provider = aws.edge
  region   = "us-east-1"
  count    = var.enable_waf ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.waf[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
