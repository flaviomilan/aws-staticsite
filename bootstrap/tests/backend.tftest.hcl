mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
variables { state_bucket_name = "example-test-state-bucket" }
run "native_locking_for_new_backend" {
  command = plan
  variables { enable_legacy_lock_table = false }
  assert {
    condition     = length(aws_dynamodb_table.terraform_locks) == 0 && aws_s3_bucket_versioning.terraform_state.versioning_configuration[0].status == "Enabled"
    error_message = "New backends need versioned state without an extra lock table."
  }
}
run "preserve_legacy_table_by_default" {
  command = plan
  assert {
    condition     = length(aws_dynamodb_table.terraform_locks) == 1
    error_message = "Existing backend migration must retain its lock table by default."
  }
}
