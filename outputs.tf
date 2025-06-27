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

# Task 2: Basic Infrastructure Configuration Outputs

output "vpc_id" {
  description = "ID utworzonego VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "Blok CIDR utworzonego VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Lista ID utworzonych podsieci publicznych."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "Lista ID utworzonych podsieci prywatnych."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "internet_gateway_id" {
  description = "ID utworzonego Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "nat_instance_public_ip" {
  description = "Publiczny adres IP instancji NAT/Bastion."
  value       = aws_eip.nat_instance.public_ip
}

output "nat_instance_sg_id" {
  description = "ID grupy bezpieczeństwa dla instancji NAT/Bastion."
  value       = aws_security_group.nat_instance.id
}

output "private_workers_sg_id" {
  description = "ID grupy bezpieczeństwa dla przyszłych workerów w podsieciach prywatnych."
  value       = aws_security_group.private_workers.id
}

output "bastion_public_ip" {
  description = "Publiczny adres IP bastiona (NAT instance z task-1)."
  value       = aws_eip.nat_instance.public_ip
}

output "k3s_nodes_private_ips" {
  description = "Prywatne adresy IP nodów k3s."
  value       = [for node in aws_instance.k3s_node : node.private_ip]
}