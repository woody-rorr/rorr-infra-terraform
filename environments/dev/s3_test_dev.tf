resource "aws_s3_bucket" "test_dev" {
  bucket = "rorr-dev-test-dev"

  tags = {
    Environment = "dev"
    Team        = "rorr"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_s3_bucket_public_access_block" "test_dev" {
  bucket = aws_s3_bucket.test_dev.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "test_dev" {
  bucket = aws_s3_bucket.test_dev.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "test_dev" {
  bucket = aws_s3_bucket.test_dev.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}
