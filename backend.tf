terraform {
  # Konfiguracja backendu S3 do przechowywania stanu Terraform zdalnie.
  # WAŻNE: Bucket zdefiniowany w variables.tf (var.s3_backend_bucket_name)
  # musi zostać utworzony PRZED pierwszym `terraform init` z tą konfiguracją backendu.
  # Można to zrobić przez tymczasowe zakomentowanie tej sekcji `backend`,
  # uruchomienie `terraform apply` w celu utworzenia bucketa, a następnie
  # odkomentowanie tej sekcji i uruchomienie `terraform init -migrate-state`.
  backend "s3" {
    bucket = "backend-tfstate-alan.kowalzky" # Nazwa bucketa dla stanu Terraform
    key    = "global/s3/terraform.tfstate"   # Klucz/ścieżka do pliku stanu w buckecie
    region = "eu-west-1"                     # Region dla bucketa stanu
    # dynamodb_table = "terraform-locks" # Opcjonalnie, dla blokowania stanu (nie wymagane w tym zadaniu)
  }
}