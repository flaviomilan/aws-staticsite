output "state_bucket_name" { value = aws_s3_bucket.terraform_state.id }
output "state_bucket_arn" { value = aws_s3_bucket.terraform_state.arn }
output "lock_table_name" { value = var.enable_legacy_lock_table ? aws_dynamodb_table.terraform_locks[0].name : null }
output "backend_config" {
  value = <<-EOT
    bucket = "${aws_s3_bucket.terraform_state.id}"
    key = "sites/SITE/ENVIRONMENT.tfstate"
    region = "${var.aws_region}"
    encrypt = true
    use_lockfile = true
  EOT
}
