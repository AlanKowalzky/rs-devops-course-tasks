# Grupa bezpieczeństwa dla instancji NAT/Bastion jest już zdefiniowana w pliku nat.tf.

# Grupa bezpieczeństwa dla przyszłych workerów K8s w podsieciach prywatnych.
resource "aws_security_group" "private_workers" {
  name        = "${var.project_name}-private-workers-sg"
  description = "Security group for K8s workers in private subnets"
  vpc_id      = aws_vpc.main.id

  # Zezwól na cały ruch przychodzący z zasobów wewnątrz tego samego VPC.
  # W środowisku produkcyjnym reguły byłyby bardziej restrykcyjne,
  # np. zezwalając na ruch tylko z określonych grup bezpieczeństwa.
  ingress {
    description = "Allow all traffic from within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # Zezwól na cały ruch wychodzący.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-private-workers-sg"
    }
  )
}