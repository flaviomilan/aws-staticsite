moved {
  from = aws_acm_certificate.cert
  to   = module.site.aws_acm_certificate.cert
}

moved {
  from = aws_acm_certificate_validation.cert
  to   = module.site.aws_acm_certificate_validation.cert
}

moved {
  from = aws_cloudfront_distribution.s3_distribution
  to   = module.site.aws_cloudfront_distribution.s3_distribution
}

moved {
  from = aws_cloudfront_origin_access_control.cloudfront_s3_oac
  to   = module.site.aws_cloudfront_origin_access_control.cloudfront_s3_oac
}

moved {
  from = aws_cloudfront_function.rewrite_index
  to   = module.site.aws_cloudfront_function.rewrite_index
}

moved {
  from = aws_cloudfront_response_headers_policy.security_headers
  to   = module.site.aws_cloudfront_response_headers_policy.security_headers
}

moved {
  from = aws_cloudfront_monitoring_subscription.monitoring
  to   = module.site.aws_cloudfront_monitoring_subscription.monitoring
}

moved {
  from = aws_sns_topic.alarms
  to   = module.site.aws_sns_topic.alarms
}

moved {
  from = aws_sns_topic_subscription.email
  to   = module.site.aws_sns_topic_subscription.email
}

moved {
  from = aws_cloudwatch_metric_alarm.cloudfront_5xx
  to   = module.site.aws_cloudwatch_metric_alarm.cloudfront_5xx
}

moved {
  from = aws_cloudwatch_metric_alarm.cloudfront_4xx
  to   = module.site.aws_cloudwatch_metric_alarm.cloudfront_4xx
}

moved {
  from = aws_cloudwatch_metric_alarm.waf_blocked
  to   = module.site.aws_cloudwatch_metric_alarm.waf_blocked
}

moved {
  from = aws_cloudwatch_dashboard.main
  to   = module.site.aws_cloudwatch_dashboard.main
}

moved {
  from = aws_route53_record.acm_validation
  to   = module.site.aws_route53_record.acm_validation
}

moved {
  from = aws_s3_bucket.s3_bucket
  to   = module.site.aws_s3_bucket.s3_bucket
}

moved {
  from = aws_s3_bucket_ownership_controls.s3_ownership
  to   = module.site.aws_s3_bucket_ownership_controls.s3_ownership
}

moved {
  from = aws_s3_bucket_public_access_block.block_public_access
  to   = module.site.aws_s3_bucket_public_access_block.block_public_access
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.s3_sse
  to   = module.site.aws_s3_bucket_server_side_encryption_configuration.s3_sse
}

moved {
  from = aws_s3_bucket_versioning.s3_versioning
  to   = module.site.aws_s3_bucket_versioning.s3_versioning
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.s3_lifecycle
  to   = module.site.aws_s3_bucket_lifecycle_configuration.s3_lifecycle
}

moved {
  from = aws_s3_bucket_policy.cdn_oac_bucket_policy
  to   = module.site.aws_s3_bucket_policy.cdn_oac_bucket_policy
}

moved {
  from = aws_wafv2_web_acl.waf
  to   = module.site.aws_wafv2_web_acl.waf
}

moved {
  from = aws_cloudwatch_log_group.waf_logs
  to   = module.site.aws_cloudwatch_log_group.waf_logs
}

moved {
  from = aws_wafv2_web_acl_logging_configuration.waf_logging
  to   = module.site.aws_wafv2_web_acl_logging_configuration.waf_logging
}

moved {
  from = aws_route53_record.record_a
  to   = module.site.aws_route53_record.record_a
}

moved {
  from = aws_route53_record.record_aaaa
  to   = module.site.aws_route53_record.record_aaaa
}

moved {
  from = aws_route53_record.www_a
  to   = module.site.aws_route53_record.www_a
}

moved {
  from = aws_route53_record.www_aaaa
  to   = module.site.aws_route53_record.www_aaaa
}

removed {
  from = aws_s3_object.upload_files
  lifecycle { destroy = false }
}
