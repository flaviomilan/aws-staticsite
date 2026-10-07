output "name_servers" {
  description = "Name servers for the Route 53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.public_zone.name_servers
}

output "bucket_id" {
  description = "The S3 bucket name."
  value       = module.site.bucket_id
}

output "bucket_arn" {
  description = "The S3 bucket ARN."
  value       = module.site.bucket_arn
}

output "bucket_regional_domain_name" {
  description = "The S3 bucket regional domain name."
  value       = module.site.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "The CloudFront distribution ID. Use for cache invalidation."
  value       = module.site.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name."
  value       = module.site.cloudfront_domain_name
}

output "acm_certificate_arn" {
  description = "The ACM certificate ARN."
  value       = module.site.acm_certificate_arn
}

output "site_url" {
  description = "The URL of the deployed site."
  value       = module.site.site_url
}

output "release_bucket_id" { value = module.site.release_bucket_id }
