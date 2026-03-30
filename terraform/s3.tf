# Single S3 bucket for all data (raw + processed + model artifacts)
resource "aws_s3_bucket" "data" {
  bucket        = "cybersec-data-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name = "ThreatDetectionData"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
