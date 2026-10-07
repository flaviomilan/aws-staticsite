variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the S3 origin; global resources use the us-east-1 provider."

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

variable "enable_waf" {
  type        = bool
  default     = false
  description = "Enable AWS WAF for the CloudFront distribution. Adds protection against common web attacks. WAF incurs usage-based charges, including in count mode."
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
  description = "Enable CloudWatch dashboard and alarms. Additional paid metrics are a separate option."
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
variable "hosted_zone_id" {
  type        = string
  description = "Existing, delegated Route53 public hosted zone ID."
}
variable "aliases" {
  type        = list(string)
  default     = []
  description = "Additional hostnames on the certificate and distribution; each must belong to the supplied zone."
  validation {
    condition     = alltrue([for host in var.aliases : can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", host))]) && length(distinct(var.aliases)) == length(var.aliases) && !contains(var.aliases, var.domain)
    error_message = "Aliases must be unique lowercase hostnames, excluding the primary domain."
  }
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
variable "canonical_domain" {
  type        = string
  default     = null
  description = "Canonical hostname; null selects domain."
  validation {
    condition     = var.canonical_domain == null ? true : contains(concat([var.domain], var.aliases), var.canonical_domain)
    error_message = "Canonical hostname must be the domain or one of its aliases."
  }
}
variable "redirect_aliases" {
  type        = bool
  default     = true
  description = "Redirect configured aliases to the canonical hostname."
}
variable "hsts_include_subdomains" {
  type        = bool
  default     = false
  description = "Enable only when every subdomain supports HTTPS."
}
variable "hsts_preload" {
  type        = bool
  default     = false
  description = "Advertise HSTS preload eligibility; does not submit the domain to the preload list."
  validation {
    condition     = !var.hsts_preload || var.hsts_include_subdomains
    error_message = "HSTS preload requires include_subdomains."
  }
}
variable "enable_additional_metrics" {
  type        = bool
  default     = false
  description = "Subscribe to paid CloudFront metrics including CacheHitRate."
}
variable "enable_access_logs" {
  type        = bool
  default     = false
  description = "Enable standard logging v2 to a private S3 bucket."
}
variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Access-log retention and WAF CloudWatch log retention."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Choose a supported CloudWatch log retention period."
  }
}
variable "waf_mode" {
  type        = string
  default     = "count"
  description = "Start in count, review logs, then change to block."
  validation {
    condition     = contains(["count", "block"], var.waf_mode)
    error_message = "waf_mode must be count or block."
  }
}
variable "block_anonymous_ips" {
  type        = bool
  default     = false
  description = "Include the managed anonymous IP rule group; may affect VPN users."
}
