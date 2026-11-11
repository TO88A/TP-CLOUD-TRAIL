# ---------------------------------------------------------------------------
# Module « bucket sécurisé » (bonus du TP).
# Garanties : 4 verrous d'accès public, chiffrement par défaut, versioning,
# TLS obligatoire, cycle de vie, journaux d'accès (sauf bucket de journaux).
#
# Les attributs dépendants référencent "aws_s3_bucket.this.bucket" (connu dès
# le plan) et non ".id" (inconnu avant apply) : Conftest peut ainsi relier
# chaque sous-ressource à son bucket dans le plan JSON.
# ---------------------------------------------------------------------------

locals {
  bucket_arn = "arn:aws:s3:::${aws_s3_bucket.this.bucket}"
}

# EXCEPTIONS DOCUMENTÉES (détail : audit/exceptions.md)
#trivy:ignore:AWS-0132 EXC-01 : KMS indisponible dans LocalStack, SSE-S3 AES256 appliqué.
#trivy:ignore:AWS-0089[bucket=novacorp-logs] EXC-04 : pas de journalisation récursive du bucket de journaux.
resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_145:KMS non disponible dans l'environnement LocalStack imposé (s3,iam,sts) ; chiffrement SSE-S3 AES256 appliqué. Exception EXC-01.
  #checkov:skip=CKV_AWS_144:Laboratoire mono-région LocalStack ; la réplication inter-région exige une 2e région + rôle IAM. Exception EXC-02.
  #checkov:skip=CKV2_AWS_62:Aucun service de notification (SNS/SQS/Lambda/EventBridge) dans l'environnement. Exception EXC-03.
  #checkov:skip=CKV_AWS_18:Les journaux d'accès sont imposés par validation pour tout bucket sauf le bucket de destination des journaux (pas de journalisation récursive). Exception EXC-04.
  bucket = var.bucket_name
  tags   = var.tags

  lifecycle {
    precondition {
      condition     = var.is_log_destination || var.access_log_target_bucket != null
      error_message = "Un bucket qui n'est pas le bucket de journaux doit définir access_log_target_bucket."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.bucket
  rule {
    object_ownership = "BucketOwnerEnforced" # désactive les ACL
  }
}

#trivy:ignore:AWS-0132 EXC-01 : KMS indisponible dans LocalStack, SSE-S3 AES256 appliqué.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "this" {
  count         = var.access_log_target_bucket == null ? 0 : 1
  bucket        = aws_s3_bucket.this.bucket
  target_bucket = var.access_log_target_bucket
  target_prefix = var.access_log_prefix
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        }
      ],
      var.is_log_destination ? [
        {
          Sid       = "AllowS3ServerAccessLogs"
          Effect    = "Allow"
          Principal = { Service = "logging.s3.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource  = "${local.bucket_arn}/s3-access/*"
          Condition = { StringEquals = { "aws:SourceAccount" = var.source_account_id } }
        }
      ] : []
    )
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket

  rule {
    id     = "retention"
    status = "Enabled"
    filter {}

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]
      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.this]
}
