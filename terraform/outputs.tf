output "logs_bucket_name" {
  description = "Nom du bucket de journaux."
  value       = module.logs_bucket.bucket_name
}

output "customer_data_bucket_name" {
  description = "Nom du bucket de données clients."
  value       = module.customer_data_bucket.bucket_name
}

output "app_writer_user_name" {
  description = "Nom de l'utilisateur IAM applicatif."
  value       = aws_iam_user.app_writer.name
}

output "app_writer_user_arn" {
  description = "ARN de l'utilisateur IAM applicatif."
  value       = aws_iam_user.app_writer.arn
}

output "app_writer_group_name" {
  description = "Groupe IAM portant la politique de moindre privilège."
  value       = aws_iam_group.app_writers.name
}

output "app_config_object" {
  description = "Emplacement de la configuration applicative (le contenu reste sensible)."
  value       = "s3://${module.customer_data_bucket.bucket_name}/${aws_s3_object.app_config.key}"
}
