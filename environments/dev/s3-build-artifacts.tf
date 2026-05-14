# S3 Bucket for Build Artifacts
# Purpose: Store build results for dev environment

resource "aws_s3_bucket" "build_artifacts" {
  bucket = "rorr-dev-build-artifacts"

  force_destroy = true  # dev only - allow destruction with objects

  tags = {
    Name        = "rorr-dev-build-artifacts"
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
    Purpose     = "build-artifacts"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
resource "aws_s3_bucket_versioning" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Lifecycle rule: move to STANDARD_IA after 30 days, delete after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "build_artifacts" {
  bucket = aws_s3_bucket.build_artifacts.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Outputs
output "build_artifacts_bucket_name" {
  description = "Name of the build artifacts S3 bucket"
  value       = aws_s3_bucket.build_artifacts.id
}

output "build_artifacts_bucket_arn" {
  description = "ARN of the build artifacts S3 bucket"
  value       = aws_s3_bucket.build_artifacts.arn
}