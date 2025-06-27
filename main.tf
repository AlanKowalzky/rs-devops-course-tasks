terraform {
  required_version = ">= 1.6.0"

  # Backend S3 jest już zdefiniowany w backend.tf
}

resource "aws_s3_bucket" "s3_backend_bucket" {
  bucket = var.s3_backend_bucket_name


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

# Lokalne zmienne dla wspólnych tagów
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "dev" # Możesz użyć zmiennej var.environment, jeśli zdefiniowana
    Terraform   = "true"
  }
}

resource "aws_s3_bucket" "application_data_bucket" {
  bucket = var.application_data_s3_bucket_name

  tags = {
    Name        = "Alank Application Data Bucket"
    Environment = "Dev"
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

# Nody k3s
resource "aws_instance" "k3s_node" {
  count                  = var.k3s_node_count
  ami                    = var.ami_id
  instance_type          = var.k3s_instance_type
  subnet_id              = element([for subnet in aws_subnet.private : subnet.id], count.index)
  key_name               = var.ssh_key_name
  tags = merge(local.common_tags, { Name = "k3s-node-${count.index + 1}" })
}