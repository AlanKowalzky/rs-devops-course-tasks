resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}