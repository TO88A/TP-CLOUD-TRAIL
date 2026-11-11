provider "aws" {
  region = var.aws_region

  # VERSION NAÏVE : identifiants écrits en dur dans le code.
  access_key = "test"
  secret_key = "test"

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
