provider "aws" {
  region = "eu-west-1" # Region z poprzedniej konfiguracji
}

resource "aws_key_pair" "minikube_key" {
  key_name   = "minikube-key"
  public_key = file("~/.ssh/id_rsa.pub") # Upewnij się, że masz klucz SSH
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
  ami           = "ami-0a0c8eebcdd6dcbd0" # Ubuntu 22.04 LTS, eu-west-1
  instance_type = "t3.small"
  key_name      = aws_key_pair.minikube_key.key_name
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]

  user_data = file("${path.module}/minikube-setup.sh")

  tags = {
    Name = "minikube-aws"
  }
}

output "public_ip" {
  value = aws_instance.minikube.public_ip
} 