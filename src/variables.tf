variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "The AWS region where the resources will be provisioned. ACM certificates for CloudFront must be in us-east-1."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Must be a valid AWS region identifier (e.g., us-east-1)."
  }
}

variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket used for hosting your application files."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Must be a valid S3 bucket name (lowercase, 3-63 characters)."
  }
}

variable "domain" {
  type        = string
  description = "The domain name for your application (e.g., example.com)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain))
    error_message = "Must be a valid domain name."
  }
}

variable "files_path" {
  type        = string
  default     = ""
  description = "Deprecated; publish artifacts with the content workflow instead."
}

variable "domain_enabled" {
  type        = bool
  default     = true
  description = "Deprecated migration input. False is rejected to prevent destruction; use examples/dns for new zones."
  validation {
    condition     = var.domain_enabled
    error_message = "domain_enabled=false is no longer supported; manage initial DNS separately."
  }
}

variable "enable_waf" {
  type        = bool
  default     = false
  description = "Enable AWS WAF for the CloudFront distribution. Adds protection against common web attacks. Note: WAF incurs additional costs (~$5/month + per-request charges)."
}

variable "project_name" {
  type        = string
  default     = "StaticSite"
  description = "Project name used for resource naming and tagging."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Environment name for resource tagging."

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "force_destroy_zone" {
  type        = bool
  default     = false
  description = "Allow destruction of the Route53 hosted zone even if it contains records. Use with caution in production."
}

variable "csp_policy" {
  type        = string
  default     = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';"
  description = "Content-Security-Policy header value. Customize based on your site's requirements."
}

variable "waf_rate_limit" {
  type        = number
  default     = 2000
  description = "Maximum number of requests per 5-minute period per IP address before WAF blocks the source."

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000."
  }
}

variable "enable_monitoring" {
  type        = bool
  default     = false
  description = "Enable dashboard and alarms; additional metrics are now independent."
}

variable "notification_email" {
  type        = string
  default     = ""
  description = "Email address for CloudWatch alarm notifications. Leave empty to disable email alerts."
}

variable "minimum_tls_version" {
  type        = string
  default     = "TLSv1.2_2021"
  description = "Minimum TLS protocol version for CloudFront viewer connections."

  validation {
    condition     = contains(["TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021"], var.minimum_tls_version)
    error_message = "TLS version must be one of: TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021."
  }
}

variable "enable_s3_versioning" {
  type        = bool
  default     = false
  description = "Enable S3 bucket versioning to keep old file versions. Adds storage costs for non-current object versions (cleaned up after 30 days via lifecycle rule)."
}
variable "routing_mode" {
  type        = string
  default     = "static"
  description = "static resolves directories; spa rewrites extensionless navigation paths to the root index."
  validation {
    condition     = contains(["static", "spa"], var.routing_mode)
    error_message = "routing_mode must be static or spa."
  }
}

variable "hsts_include_subdomains" {
  type        = bool
  default     = true
  description = "Enable only when every subdomain supports HTTPS."
}

variable "hsts_preload" {
  type        = bool
  default     = true
  description = "Advertise HSTS preload eligibility; does not submit the domain to the preload list."
  validation {
    condition     = !var.hsts_preload || var.hsts_include_subdomains
    error_message = "HSTS preload requires include_subdomains."
  }
}

variable "redirect_aliases" {
  type        = bool
  default     = false
  description = "Redirect configured aliases to the canonical hostname."
}

variable "enable_access_logs" {
  type        = bool
  default     = false
  description = "Enable standard logging v2 to a private S3 bucket."
}

variable "enable_additional_metrics" {
  type        = bool
  default     = null
  description = "Subscribe to paid CloudFront metrics including CacheHitRate."
}
