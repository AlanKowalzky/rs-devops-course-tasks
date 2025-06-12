terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Możesz dostosować do najnowszej stabilnej wersji
    }
  }
}

provider "aws" {
  region = var.aws_region
}