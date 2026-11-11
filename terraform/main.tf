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
  bucket       = aws_s3_bucket.customer_data.id
  key          = "config/app.json"
  content_type = "application/json"
  content = jsonencode({
    db_host     = "db.novacorp.internal"
    db_user     = "app"
    db_password = var.db_password
  })
}
