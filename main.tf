resource "aws_s3_bucket" "s3_backend_bucket" {
  bucket = var.s3_backend_bucket_name

  # Włączenie wersjonowania dla bezpieczeństwa pliku stanu
  versioning {
    enabled = true
  }

  # Konfiguracja szyfrowania po stronie serwera
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  # Zapobiega przypadkowemu usunięciu bucketa, jeśli jest to wymagane
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Name = "Terraform State Bucket for DevOps Course"
  }
}

resource "aws_s3_bucket" "application_data_bucket" {
  bucket = var.application_data_s3_bucket_name

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  # Możesz dodać inne konfiguracje specyficzne dla tego bucketa, np.
  # aws_s3_bucket_public_access_block, aws_s3_bucket_acl, etc.

  tags = {
    Name        = "Alank Application Data Bucket"
    Environment = "Dev" # Przykładowy tag
  }
}