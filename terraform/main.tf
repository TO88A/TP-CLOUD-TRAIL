# ---------------------------------------------------------------------------
# VERSION NAÏVE — volontairement non sécurisée (Partie 1 du TP).
#   - aucun chiffrement, aucun blocage de l'accès public, pas de versioning
#   - politique IAM avec Action = "*" et Resource = "*"
#   - aucune étiquette
# ---------------------------------------------------------------------------

locals {
  # Étiquettes obligatoires appliquées à CHAQUE ressource étiquetable.
  common_tags = {
    owner   = var.owner
    env     = var.environment
    project = var.project_name
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs"
  tags   = merge(local.common_tags, { data_class = "logs" })
}

resource "aws_s3_bucket" "customer_data" {
  bucket = "${var.project_name}-customer-data"
  tags   = merge(local.common_tags, { data_class = "confidential" })
}

resource "aws_iam_user" "app_writer" {
  name = "app-writer"
  tags = local.common_tags
}

# Moindre privilège : la politique est portée par un GROUPE (CKV_AWS_40 /
# AWS-0143) et n'autorise QUE l'écriture d'objets sous le préfixe app/ du
# bucket de journaux. L'ARN est construit à partir de ".bucket" (connu au
# plan) pour que Conftest puisse vérifier la politique avant apply.
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
        Resource = "arn:aws:s3:::${aws_s3_bucket.logs.bucket}/app/*"
      }
    ]
  })
}

resource "aws_iam_user_group_membership" "app_writer" {
  user   = aws_iam_user.app_writer.name
  groups = [aws_iam_group.app_writers.name]
}

# Configuration de l'application déposée dans le bucket de données
resource "aws_s3_object" "app_config" {
  bucket                 = aws_s3_bucket.customer_data.bucket
  key                    = "config/app.json"
  content_type           = "application/json"
  server_side_encryption = "AES256"
  content = jsonencode({
    db_host     = "db.novacorp.internal"
    db_user     = "app"
    db_password = var.db_password
  })
  tags = local.common_tags
}

# --- Blocage de l'accès public (les 4 verrous) sur les deux buckets ---------
# On référence ".bucket" (connu dès le plan) plutôt que ".id" (inconnu avant
# apply) : les règles Conftest peuvent ainsi relier chaque verrou à son bucket.
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "customer_data" {
  bucket                  = aws_s3_bucket.customer_data.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Chiffrement par défaut (SSE-S3 / AES256) ---------------------------------
# KMS n'est pas activé dans LocalStack (SERVICES=s3,iam,sts) : on utilise le
# chiffrement S3 géré (AES256). L'exigence de clé CMK est traitée en exception.
resource "aws_s3_bucket_server_side_encryption_configuration" "customer_data" {
  bucket = aws_s3_bucket.customer_data.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Versioning ---------------------------------------------------------------
resource "aws_s3_bucket_versioning" "customer_data" {
  bucket = aws_s3_bucket.customer_data.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Traçabilité : journaux d'accès S3 du bucket de données -> novacorp-logs --
resource "aws_s3_bucket_logging" "customer_data" {
  bucket        = aws_s3_bucket.customer_data.bucket
  target_bucket = aws_s3_bucket.logs.bucket
  target_prefix = "s3-access/customer-data/"
}

data "aws_caller_identity" "current" {}

# --- Politiques de bucket : TLS obligatoire + dépôt des journaux d'accès ------
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${aws_s3_bucket.logs.bucket}", "arn:aws:s3:::${aws_s3_bucket.logs.bucket}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AllowS3ServerAccessLogs"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.logs.bucket}/s3-access/*"
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_policy" "customer_data" {
  bucket = aws_s3_bucket.customer_data.bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${aws_s3_bucket.customer_data.bucket}", "arn:aws:s3:::${aws_s3_bucket.customer_data.bucket}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.customer_data]
}

# --- Cycle de vie -------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.bucket

  rule {
    id     = "logs-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "customer_data" {
  bucket = aws_s3_bucket.customer_data.bucket

  rule {
    id     = "customer-data-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
