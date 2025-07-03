# Wyszukanie najnowszego AMI Amazon Linux 2, które jest dobrym kandydatem na instancję NAT.
data "aws_ami" "amazon_linux_nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Grupa bezpieczeństwa dla instancji NAT.
resource "aws_security_group" "nat_instance" {
  name        = "${var.project_name}-nat-instance-sg"
  description = "Zezwala na ruch z podsieci prywatnych do instancji NAT"
  vpc_id      = aws_vpc.main.id

  # Ruch przychodzący z podsieci prywatnych.
  ingress {
    description = "Allow traffic from private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidr_blocks
  }

  # Opcjonalnie: Zezwól na SSH z Twojego IP do zarządzania instancją.
  ingress {
    description = "Allow SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_for_ssh]
  }

  # Ruch wychodzący do internetu.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nat-instance-sg"
    }
  )
}

# Instancja EC2 pełniąca rolę NAT.
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_nat.id
  instance_type               = var.nat_instance_type
  # Umieść w pierwszej publicznej podsieci.
  subnet_id                   = values(aws_subnet.public)[0].id
  associate_public_ip_address = true # Potrzebne, aby instancja miała dostęp do internetu na starcie.
  source_dest_check           = false # KLUCZOWE: Wyłącza sprawdzanie, czy ta instancja jest źródłem/celem pakietów.
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  key_name                    = var.ssh_key_name # Nazwa pary kluczy SSH w AWS.

  # Skrypt uruchamiany przy starcie instancji, konfigurujący NAT.
  user_data = <<-EOF
                #!/bin/bash
                # Włącz przekazywanie pakietów IP
                echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
                sysctl -p
                # Skonfiguruj iptables do maskarady (NAT)
                /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
                # Zapisz reguły iptables, aby przetrwały restart
                yum install -y iptables-services
                service iptables save
                chkconfig iptables on
                EOF

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nat-instance"
    }
  )

  # Jawna zależność od IGW, aby upewnić się, że publiczna podsieć ma łączność.
  depends_on = [aws_internet_gateway.main]
}

# Elastic IP dla instancji NAT, aby miała stały publiczny adres IP.
resource "aws_eip" "nat_instance" {
  instance = aws_instance.nat.id
  domain   = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nat-instance-eip"
    }
  )
}