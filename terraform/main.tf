# ---------------------------------------------------------------------------
# VERSION SÉCURISÉE (branche `secure`).
# Les deux buckets sont décrits par le module réutilisable modules/secure-bucket
# (bonus). Les blocs `moved` (moves.tf) garantissent que le passage au module
# ne détruit/recrée AUCUN bucket.
# ---------------------------------------------------------------------------

locals {
  # Étiquettes obligatoires appliquées à CHAQUE ressource étiquetable.
  common_tags = {
    owner   = var.owner
    env     = var.environment
    project = var.project_name
  }

  logs_bucket_name          = "${var.project_name}-logs"
  customer_data_bucket_name = "${var.project_name}-customer-data"
}

data "aws_caller_identity" "current" {}

# --- Buckets -----------------------------------------------------------------
module "logs_bucket" {
  source = "./modules/secure-bucket"

  bucket_name        = local.logs_bucket_name
  tags               = merge(local.common_tags, { data_class = "logs" })
  is_log_destination = true
  source_account_id  = data.aws_caller_identity.current.account_id

  expiration_days         = 365 # rétention des journaux : 1 an
  noncurrent_version_days = 30
}

module "customer_data_bucket" {
  source = "./modules/secure-bucket"

  bucket_name              = local.customer_data_bucket_name
  tags                     = merge(local.common_tags, { data_class = "confidential" })
  access_log_target_bucket = module.logs_bucket.bucket_name
  access_log_prefix        = "s3-access/customer-data/"

  noncurrent_version_days = 90
}

# --- IAM : moindre privilège ---------------------------------------------------
resource "aws_iam_user" "app_writer" {
  #checkov:skip=CKV_AWS_273:L'énoncé impose un utilisateur IAM app-writer ; en production : rôle IAM assumé (OIDC/IRSA). Exception EXC-05.
  name = "app-writer"
  tags = local.common_tags
}

# La politique est portée par un GROUPE (CKV_AWS_40 / AWS-0143) et n'autorise
# QUE l'écriture d'objets sous le préfixe app/ du bucket de journaux.
# L'ARN est construit (connu au plan) pour que Conftest puisse le vérifier.
#trivy:ignore:AWS-0123 EXC-06 : compte de service sans console ; la MFA s'applique aux humains, pas aux clés d'application.
resource "aws_iam_group" "app_writers" {
  name = "app-writers"
}

resource "aws_iam_group_policy" "app_writers_logs_write" {
  name  = "app-writers-logs-write"
  group = aws_iam_group.app_writers.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteAppLogsOnly"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${module.logs_bucket.bucket_arn}/app/*"
      }
    ]
  })
}

resource "aws_iam_user_group_membership" "app_writer" {
  user   = aws_iam_user.app_writer.name
  groups = [aws_iam_group.app_writers.name]
}

# --- Configuration applicative (secret fourni hors dépôt) ---------------------
resource "aws_s3_object" "app_config" {
  bucket                 = module.customer_data_bucket.bucket_name
  key                    = "config/app.json"
  content_type           = "application/json"
  server_side_encryption = "AES256"
  content = jsonencode({
    db_host     = "db.novacorp.internal"
    db_user     = "app"
    db_password = var.db_password # variable sensitive, valeur hors dépôt
  })
  tags = local.common_tags
}
