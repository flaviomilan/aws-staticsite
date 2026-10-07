# Maintenance policy for an already-created site, not account/bootstrap administration.
locals {
  account      = data.aws_caller_identity.current.account_id
  log_bucket   = "${substr(var.bucket_name, 0, 48)}-log-${substr(sha256(var.bucket_name), 0, 6)}"
  site_buckets = concat([var.bucket_name, var.release_bucket_name], var.enable_access_logs ? [local.log_bucket] : [])
  infrastructure_statements = concat([
    {
      Sid       = "StateBucket"
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = "arn:aws:s3:::${var.state_bucket_name}"
      Condition = { StringLike = { "s3:prefix" = [var.site_state_key, "${var.site_state_key}.tflock", "env:/"] } }
    },
    {
      Sid      = "SiteState"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::${var.state_bucket_name}/${var.site_state_key}"
    },
    {
      Sid      = "SiteLock"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::${var.state_bucket_name}/${var.site_state_key}.tflock"
    },
    {
      Sid      = "SiteBucketConfiguration"
      Effect   = "Allow"
      Action   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketAcl", "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:GetBucketTagging", "s3:PutBucketTagging", "s3:GetBucketVersioning", "s3:PutBucketVersioning", "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration", "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration", "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock", "s3:GetBucketOwnershipControls", "s3:PutBucketOwnershipControls", "s3:DeleteBucketOwnershipControls", "s3:GetBucketCORS", "s3:GetBucketWebsite", "s3:GetBucketLogging", "s3:GetAccelerateConfiguration", "s3:GetBucketRequestPayment", "s3:GetBucketObjectLockConfiguration", "s3:GetReplicationConfiguration"]
      Resource = [for name in local.site_buckets : "arn:aws:s3:::${name}"]
    },
    {
      Sid      = "ExistingDistribution"
      Effect   = "Allow"
      Action   = ["cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:UpdateDistribution", "cloudfront:ListTagsForResource", "cloudfront:TagResource", "cloudfront:UntagResource"]
      Resource = "arn:aws:cloudfront::${local.account}:distribution/${var.distribution_id}"
    },
    {
      Sid      = "SupportingCloudFrontResources"
      Effect   = "Allow"
      Action   = ["cloudfront:CreateFunction", "cloudfront:CreateOriginAccessControl", "cloudfront:GetOriginAccessControl", "cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl", "cloudfront:CreateCachePolicy", "cloudfront:GetCachePolicy", "cloudfront:GetCachePolicyConfig", "cloudfront:UpdateCachePolicy", "cloudfront:DeleteCachePolicy", "cloudfront:CreateResponseHeadersPolicy", "cloudfront:GetResponseHeadersPolicy", "cloudfront:GetResponseHeadersPolicyConfig", "cloudfront:UpdateResponseHeadersPolicy", "cloudfront:DeleteResponseHeadersPolicy"]
      Resource = "*"
    },
    {
      Sid      = "SiteFunction"
      Effect   = "Allow"
      Action   = ["cloudfront:DescribeFunction", "cloudfront:GetFunction", "cloudfront:UpdateFunction", "cloudfront:PublishFunction", "cloudfront:DeleteFunction"]
      Resource = "arn:aws:cloudfront::${local.account}:function/${replace("rewrite-index-${var.domain}", ".", "-")}"
    },
    {
      Sid      = "CertificateLifecycle"
      Effect   = "Allow"
      Action   = ["acm:DescribeCertificate", "acm:DeleteCertificate", "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate", "acm:ListTagsForCertificate"]
      Resource = "arn:aws:acm:us-east-1:${local.account}:certificate/*"
    },
    {
      Sid      = "RequestSiteCertificate"
      Effect   = "Allow"
      Action   = ["acm:RequestCertificate"]
      Resource = "*"
      Condition = {
        StringEquals                = { "aws:RequestedRegion" = "us-east-1", "acm:ValidationMethod" = "DNS" }
        "ForAllValues:StringEquals" = { "acm:DomainNames" = concat([var.domain], var.aliases) }
      }
    },
    {
      Sid      = "ZoneRecords"
      Effect   = "Allow"
      Action   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ChangeResourceRecordSets", "route53:ListTagsForResource"]
      Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
    },
    {
      Sid      = "DNSChangeStatus"
      Effect   = "Allow"
      Action   = ["route53:GetChange"]
      Resource = "arn:aws:route53:::change/*"
    }
    ], var.enable_additional_metrics ? [{
      Sid      = "AdditionalMetrics"
      Effect   = "Allow"
      Action   = ["cloudfront:CreateMonitoringSubscription", "cloudfront:GetMonitoringSubscription", "cloudfront:DeleteMonitoringSubscription"]
      Resource = "*"
    }] : [], var.enable_monitoring ? [
    {
      Sid      = "SiteAlarms"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DescribeAlarms", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource"]
      Resource = "arn:aws:cloudwatch:us-east-1:${local.account}:alarm:${var.domain}-*"
    },
    {
      Sid      = "SiteDashboard"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutDashboard", "cloudwatch:GetDashboard", "cloudwatch:DeleteDashboards"]
      Resource = "arn:aws:cloudwatch::${local.account}:dashboard/${replace(var.domain, ".", "-")}-dashboard"
    },
    {
      Sid      = "SiteNotificationTopic"
      Effect   = "Allow"
      Action   = ["sns:CreateTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:DeleteTopic", "sns:ListTagsForResource", "sns:TagResource", "sns:UntagResource", "sns:Subscribe", "sns:ListSubscriptionsByTopic"]
      Resource = "arn:aws:sns:us-east-1:${local.account}:${replace(var.domain, ".", "-")}-alarms"
    },
    {
      Sid      = "NotificationSubscriptionMaintenance"
      Effect   = "Allow"
      Action   = ["sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes", "sns:Unsubscribe"]
      Resource = "*"
    }
    ] : [], var.enable_waf ? [
    {
      Sid      = "SiteWAF"
      Effect   = "Allow"
      Action   = ["wafv2:CreateWebACL", "wafv2:GetWebACL", "wafv2:UpdateWebACL", "wafv2:DeleteWebACL", "wafv2:ListTagsForResource", "wafv2:TagResource", "wafv2:UntagResource", "wafv2:PutLoggingConfiguration", "wafv2:GetLoggingConfiguration", "wafv2:DeleteLoggingConfiguration"]
      Resource = "arn:aws:wafv2:us-east-1:${local.account}:global/webacl/waf-${replace(var.domain, ".", "-")}/*"
    },
    {
      Sid      = "WAFLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:DescribeLogGroups", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource", "logs:ListTagsLogGroup", "logs:TagLogGroup", "logs:UntagLogGroup"]
      Resource = "arn:aws:logs:us-east-1:${local.account}:log-group:aws-waf-logs-${replace(var.domain, ".", "-")}*"
    },
    {
      Sid      = "WAFLoggingDelivery"
      Effect   = "Allow"
      Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
      Resource = "*"
    }
    ] : [], var.enable_access_logs ? [
    {
      Sid      = "CloudFrontLogDelivery"
      Effect   = "Allow"
      Action   = ["logs:PutDeliverySource", "logs:GetDeliverySource", "logs:DeleteDeliverySource", "logs:PutDeliveryDestination", "logs:GetDeliveryDestination", "logs:DeleteDeliveryDestination", "logs:CreateDelivery", "logs:GetDelivery", "logs:DeleteDelivery", "logs:UpdateDeliveryConfiguration", "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource"]
      Resource = "arn:aws:logs:us-east-1:${local.account}:*"
    },
    {
      Sid      = "EnableDistributionLogDelivery"
      Effect   = "Allow"
      Action   = ["cloudfront:AllowVendedLogDeliveryForResource"]
      Resource = "arn:aws:cloudfront::${local.account}:distribution/${var.distribution_id}"
    }
  ] : [])
}
