output "logs_bucket_name" {
  description = "Nom du bucket de journaux."
  value       = aws_s3_bucket.logs.bucket
}

output "customer_data_bucket_name" {
  description = "Nom du bucket de données clients."
  value       = aws_s3_bucket.customer_data.bucket
}

output "app_writer_user_name" {
  description = "Nom de l'utilisateur IAM applicatif."
  value       = aws_iam_user.app_writer.name
}

output "app_writer_user_arn" {
  description = "ARN de l'utilisateur IAM applicatif."
  value       = aws_iam_user.app_writer.arn
}
