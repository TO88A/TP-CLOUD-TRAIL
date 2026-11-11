output "bucket_name" {
  description = "Nom du bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN du bucket (construit, connu dès le plan)."
  value       = local.bucket_arn
}
