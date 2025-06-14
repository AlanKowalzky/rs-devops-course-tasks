output "s3_backend_bucket_id" {
  description = "ID (nazwa) bucketa S3 używanego do przechowywania stanu Terraform."
  value       = aws_s3_bucket.s3_backend_bucket.id
}

output "s3_backend_bucket_arn" {
  description = "ARN bucketa S3 używanego do przechowywania stanu Terraform."
  value       = aws_s3_bucket.s3_backend_bucket.arn
}

output "application_data_s3_bucket_id" {
  description = "ID (nazwa) bucketa S3 używanego dla danych aplikacji."
  value       = aws_s3_bucket.application_data_bucket.id
}

output "application_data_s3_bucket_arn" {
  description = "ARN bucketa S3 używanego dla danych aplikacji."
  value       = aws_s3_bucket.application_data_bucket.arn
}