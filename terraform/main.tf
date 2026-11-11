# ---------------------------------------------------------------------------
# VERSION NAÏVE — volontairement non sécurisée (Partie 1 du TP).
#   - aucun chiffrement, aucun blocage de l'accès public, pas de versioning
#   - politique IAM avec Action = "*" et Resource = "*"
#   - aucune étiquette
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs"
}

resource "aws_s3_bucket" "customer_data" {
  bucket = "${var.project_name}-customer-data"
}

resource "aws_iam_user" "app_writer" {
  name = "app-writer"
}

resource "aws_iam_user_policy" "app_writer" {
  name = "app-writer-policy"
  user = aws_iam_user.app_writer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
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
