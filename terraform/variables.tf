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

variable "db_password" {
  description = "Mot de passe applicatif de la base. Fourni HORS dépôt (TF_VAR_db_password, via le fichier .env non versionné)."
  type        = string
  sensitive   = true
  # Pas de valeur par défaut : Terraform échoue si la valeur n'est pas fournie.

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password doit contenir au moins 16 caractères."
  }
}

variable "owner" {
  description = "Équipe propriétaire des ressources (étiquette obligatoire owner)."
  type        = string
  default     = "team-platform"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner ne peut pas être vide."
  }
}
