variable "aws_region" {
  description = "Region AWS, w którym będą wdrażane zasoby."
  type        = string
  default     = "eu-west-1" # Zmieniono domyślny region na eu-west-1
}

variable "s3_backend_bucket_name" {
  description = "Nazwa bucketa S3 dla przechowywania stanu Terraform. Musi być globalnie unikalna."
  type        = string
  default     = "backend-tfstate-alan.kowalzky" # WAŻNE: Zmień na unikalną nazwę zgodną z backend.tf!
}

variable "application_data_s3_bucket_name" {
  description = "Nazwa bucketa S3 dla danych aplikacji. Musi być globalnie unikalna."
  type        = string
  default     = "application-data-alan.kowalzky" # WAŻNE: Zmień na unikalną nazwę!
}

variable "github_actions_role_name" {
  description = "Nazwa roli IAM dla GitHub Actions."
  type        = string
  default     = "GithubActionsRole"
}

variable "github_org_or_user" {
  description = "Twoja nazwa użytkownika GitHub lub nazwa organizacji."
  type        = string
  default     = "AlanKowalzky" # Zaktualizowano wielkość liter
}

variable "github_repo_name" {
  description = "Nazwa Twojego repozytorium GitHub."
  type        = string
  default     = "rs-devops-course-tasks" # Lub inna nazwa, jeśli repozytorium jest inne
}

variable "project_name" {
  description = "Nazwa projektu używana w tagach i nazwach zasobów."
  type        = string
  default     = "k8s-infra" # Możesz zmienić na preferowaną nazwę projektu
}

# Task 2: Basic Infrastructure Configuration Variables

variable "vpc_cidr_block" {
  description = "Blok CIDR dla VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Lista stref dostępności do użycia (minimum 2). Terraform automatycznie wybierze dostępne AZ w danym regionie."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"] # Przykładowe AZ dla eu-west-1, dostosuj w razie potrzeby
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Należy podać co najmniej dwie strefy dostępności."
  }
}

variable "public_subnet_cidr_blocks" {
  description = "Lista bloków CIDR dla podsieci publicznych (tyle samo co AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr_blocks" {
  description = "Lista bloków CIDR dla podsieci prywatnych (tyle samo co AZ)."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}