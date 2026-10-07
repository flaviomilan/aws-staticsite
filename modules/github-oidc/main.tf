terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.38" } }
}
variable "repository" {
  type        = string
  description = "GitHub owner/repository."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "Supply owner/repository, without wildcards."
  }
}
variable "environment" {
  type        = string
  description = "Protected GitHub environment name (without colons)."
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.environment))
    error_message = "Use an environment name containing letters, digits, underscores or dashes."
  }
}
variable "branch" {
  type    = string
  default = "main"
  validation {
    condition     = can(regex("^[A-Za-z0-9_./-]+$", var.branch))
    error_message = "Supply a branch without OIDC wildcard characters."
  }
}
variable "name_prefix" { type = string }
variable "oidc_provider_arn" {
  type        = string
  description = "Existing GitHub IAM OIDC provider ARN; one provider can serve many sites."
}
variable "bucket_arn" { type = string }
variable "release_bucket_arn" { type = string }
variable "distribution_arn" { type = string }
variable "infrastructure_policy_json" {
  type        = string
  description = "Account-reviewed infrastructure permissions. No AdministratorAccess default."
  validation {
    condition     = can(jsondecode(var.infrastructure_policy_json))
    error_message = "Supply a valid IAM policy JSON document."
  }
}
data "aws_iam_policy_document" "trust" {
  for_each = toset(["infrastructure", "publish"])
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.key == "publish" ? ["repo:${var.repository}:environment:${var.environment}"] : ["repo:${var.repository}:environment:${var.environment}", "repo:${var.repository}:ref:refs/heads/${var.branch}"]
    }
  }
}
resource "aws_iam_role" "github" {
  for_each           = data.aws_iam_policy_document.trust
  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = each.value.json
}
resource "aws_iam_role_policy" "infrastructure" {
  role   = aws_iam_role.github["infrastructure"].id
  policy = var.infrastructure_policy_json
}
data "aws_iam_policy_document" "publish" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn, var.release_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.bucket_arn}/*", "${var.release_bucket_arn}/*"]
  }
  statement {
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:GetDistribution"]
    resources = [var.distribution_arn]
  }
}
resource "aws_iam_role_policy" "publish" {
  role   = aws_iam_role.github["publish"].id
  policy = data.aws_iam_policy_document.publish.json
}
output "infrastructure_role_arn" { value = aws_iam_role.github["infrastructure"].arn }
output "publication_role_arn" { value = aws_iam_role.github["publish"].arn }
