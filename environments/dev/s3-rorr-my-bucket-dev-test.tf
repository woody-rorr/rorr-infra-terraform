resource "aws_s3_bucket" "rorr_my_bucket_dev_test" {
  bucket        = "rorr-my-bucket-dev-test"
  force_destroy = false

  tags = {
    Environment = "dev"
    Team        = "TODO: 팀명 입력"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_s3_bucket_public_access_block" "rorr_my_bucket_dev_test" {
  bucket = aws_s3_bucket.rorr_my_bucket_dev_test.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rorr_my_bucket_dev_test" {
  bucket = aws_s3_bucket.rorr_my_bucket_dev_test.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "rorr_my_bucket_dev_test" {
  bucket = aws_s3_bucket.rorr_my_bucket_dev_test.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "rorr_my_bucket_dev_test" {
  bucket = aws_s3_bucket.rorr_my_bucket_dev_test.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}
