data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = "${substr(var.bucket_name, 0, 48)}-log-${substr(sha256(var.bucket_name), 0, 6)}"
  tags   = local.project_tags
}
resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = var.enable_access_logs ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration { days = var.log_retention_days }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
data "aws_iam_policy_document" "logs" {
  count = var.enable_access_logs ? 1 : 0
  statement {
    sid       = "LogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
  statement {
    sid       = "LogDeliveryCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs[0].arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs[0].arn, "${aws_s3_bucket.logs[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_s3_bucket_policy" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.logs[0].json
}
resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  provider     = aws.edge
  region       = "us-east-1"
  count        = var.enable_access_logs ? 1 : 0
  name         = "${var.bucket_name}-access"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.s3_distribution[0].arn
  tags         = local.project_tags
}
resource "aws_cloudwatch_log_delivery_destination" "s3" {
  provider      = aws.edge
  region        = "us-east-1"
  count         = var.enable_access_logs ? 1 : 0
  name          = "${var.bucket_name}-logs"
  output_format = "json"
  delivery_destination_configuration { destination_resource_arn = aws_s3_bucket.logs[0].arn }
  tags       = local.project_tags
  depends_on = [aws_s3_bucket_policy.logs]
}
resource "aws_cloudwatch_log_delivery" "cloudfront" {
  provider                 = aws.edge
  region                   = "us-east-1"
  count                    = var.enable_access_logs ? 1 : 0
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.s3[0].arn
  tags                     = local.project_tags
}
