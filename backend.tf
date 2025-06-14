terraform {
  backend "s3" {
    bucket = "backend-tfstate-alan.kowalzky"
    key    = "global/s3/terraform.tfstate"
    region = "eu-west-1"
  }
}