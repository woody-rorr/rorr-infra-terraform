# S3 Test Bucket for Development

resource "aws_s3_bucket" "test" {
  bucket = "rorr-dev-test"

  tags = {
    Name        = "rorr-dev-test"
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "test" {
  bucket = aws_s3_bucket.test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "test" {
  bucket = aws_s3_bucket.test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "test_bucket_name" {
  value       = aws_s3_bucket.test.id
  description = "Name of the test S3 bucket"
}

output "test_bucket_arn" {
  value       = aws_s3_bucket.test.arn
  description = "ARN of the test S3 bucket"
}
