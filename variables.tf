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