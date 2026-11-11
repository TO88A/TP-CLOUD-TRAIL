terraform {
  # Version minimale de Terraform
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Épinglé sur la version majeure 6 ; la version exacte (6.69.1)
      # est figée par .terraform.lock.hcl (versionné).
      version = "~> 6.0"
    }
  }
}
