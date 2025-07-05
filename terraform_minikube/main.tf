provider "aws" {
  region = "eu-west-1"
}

data "aws_vpc" "default" {
  default = true
}

# Pobierz wszystkie subnety w domyślnej VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "minikube_key" {
  key_name   = "minikube-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "minikube_sg" {
  name        = "minikube-sg"
  description = "Allow SSH, NodePort, HTTP/HTTPS"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "minikube" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.minikube_key.key_name
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  subnet_id     = data.aws_subnets.default.ids[0]
  user_data     = file("${path.module}/minikube-setup.sh")
  tags = {
    Name = "minikube-aws"
  }
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

output "public_ip" {
  value = aws_instance.minikube.public_ip
}

output "debug_vpc_id" {
  value = data.aws_vpc.default.id
}

output "debug_subnet_ids" {
  value = data.aws_subnets.default.ids
} 