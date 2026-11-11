variable "bucket_name" {
  description = "Nom du bucket S3."
  type        = string
}

variable "tags" {
  description = "Étiquettes appliquées au bucket. Doivent contenir owner et env."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["owner", "env"] : length(trimspace(lookup(var.tags, k, ""))) > 0])
    error_message = "Les étiquettes owner et env sont obligatoires et non vides."
  }
}

variable "is_log_destination" {
  description = "true pour le bucket qui RÉCEPTIONNE les journaux d'accès S3 (il ne journalise pas vers lui-même, et autorise le service de journalisation S3 à y écrire)."
  type        = bool
  default     = false
}

variable "access_log_target_bucket" {
  description = "Bucket de destination des journaux d'accès. Obligatoire sauf pour le bucket de journaux lui-même."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Préfixe des journaux d'accès dans le bucket de destination."
  type        = string
  default     = "s3-access/"
}

variable "source_account_id" {
  description = "Compte autorisé à livrer des journaux d'accès (si is_log_destination)."
  type        = string
  default     = null
}

variable "expiration_days" {
  description = "Expiration des objets courants (null = jamais)."
  type        = number
  default     = null
}

variable "noncurrent_version_days" {
  description = "Expiration des versions non courantes."
  type        = number
  default     = 90
}
