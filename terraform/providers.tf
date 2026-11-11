provider "aws" {
  region = var.aws_region

  # Aucun identifiant dans le code : ils sont lus dans l'environnement
  # (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = valeurs factices test/test,
  # exportées par scripts/tools.sh).

  # LocalStack : pas de vrai compte AWS
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    iam = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}
