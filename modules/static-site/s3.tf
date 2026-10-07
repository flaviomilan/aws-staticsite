# --------------------------------------------------------------
# S3 Bucket for Static Site
# --------------------------------------------------------------

resource "aws_s3_bucket" "s3_bucket" {
  count = 1

  bucket = var.bucket_name
  tags   = local.project_tags
}

resource "aws_s3_bucket_ownership_controls" "s3_ownership" {
  count = 1

  bucket = aws_s3_bucket.s3_bucket[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  count = 1

  bucket = aws_s3_bucket.s3_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_sse" {
  count = 1

  bucket = aws_s3_bucket.s3_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "s3_versioning" {
  count = var.enable_s3_versioning ? 1 : 0

  bucket = aws_s3_bucket.s3_bucket[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle" {
  count = var.enable_s3_versioning ? 1 : 0

  bucket = aws_s3_bucket.s3_bucket[0].id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "cdn_oac_bucket_policy" {
  count = 1

  bucket = aws_s3_bucket.s3_bucket[0].id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}
