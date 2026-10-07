locals {
  s3_origin_id = "${var.project_name}-s3-origin"

  project_tags = {
    Name        = var.project_name
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }

}
