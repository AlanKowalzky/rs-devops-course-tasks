resource "aws_s3_bucket" "s3_backend_bucket" {
  bucket = var.s3_backend_bucket_name

  # Zapobiega przypadkowemu usunięciu bucketa, jeśli jest to wymagane
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Name = "Terraform State Bucket for DevOps Course"
  }
}

resource "aws_s3_bucket_versioning" "s3_backend_bucket_versioning" {
  bucket = aws_s3_bucket.s3_backend_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_backend_bucket_sse" {
  bucket = aws_s3_bucket.s3_backend_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "application_data_bucket" {
  bucket = var.application_data_s3_bucket_name

  # Możesz dodać inne konfiguracje specyficzne dla tego bucketa, np.
  # aws_s3_bucket_public_access_block, aws_s3_bucket_acl, etc.

  tags = {
    Name        = "Alank Application Data Bucket"
    Environment = "Dev" # Przykładowy tag
  }
}

resource "aws_s3_bucket_versioning" "application_data_bucket_versioning" {
  bucket = aws_s3_bucket.application_data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "application_data_bucket_sse" {
  bucket = aws_s3_bucket.application_data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}