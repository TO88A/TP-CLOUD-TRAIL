variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe des ressources."
  type        = string
  default     = "novacorp"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name : 3 à 20 caractères parmi a-z, 0-9 et '-'."
  }
}

variable "environment" {
  description = "Environnement de déploiement."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit valoir dev, staging ou prod."
  }
}

variable "aws_region" {
  description = "Région AWS (émulée par LocalStack)."
  type        = string
  default     = "eu-west-3"
}

variable "localstack_endpoint" {
  description = "Point d'accès LocalStack pour s3, iam et sts."
  type        = string
  default     = "http://localhost:4566"
}
