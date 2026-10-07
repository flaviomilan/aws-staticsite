output "bucket_id" {
  description = "The S3 bucket name."
  value       = aws_s3_bucket.s3_bucket[0].id
}

output "bucket_arn" {
  description = "The S3 bucket ARN."
  value       = aws_s3_bucket.s3_bucket[0].arn
}

output "bucket_regional_domain_name" {
  description = "The S3 bucket regional domain name."
  value       = aws_s3_bucket.s3_bucket[0].bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "The CloudFront distribution ID. Use for cache invalidation."
  value       = aws_cloudfront_distribution.s3_distribution[0].id
}

output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.s3_distribution[0].domain_name
}

output "acm_certificate_arn" {
  description = "The ACM certificate ARN."
  value       = aws_acm_certificate.cert[0].arn
}

output "site_url" {
  description = "The URL of the deployed site."
  value       = "https://${var.domain}"
}

output "release_bucket_id" { value = aws_s3_bucket.releases.id }

output "enabled_features" {
  description = "Enabled optional resources, for cost/operations reporting."
  value = {
    waf                = length(aws_wafv2_web_acl.waf) > 0
    monitoring         = length(aws_cloudwatch_dashboard.main) > 0
    additional_metrics = length(aws_cloudfront_monitoring_subscription.monitoring) > 0
    access_logs        = length(aws_cloudwatch_log_delivery.cloudfront) > 0
    versioning         = length(aws_s3_bucket_versioning.s3_versioning) > 0
  }
}
