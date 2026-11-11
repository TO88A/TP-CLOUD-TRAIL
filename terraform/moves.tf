# Refactorisation vers le module secure-bucket SANS destruction :
# chaque adresse existante dans le state est déplacée vers sa nouvelle adresse.

# --- novacorp-logs ---
moved {
  from = aws_s3_bucket.logs
  to   = module.logs_bucket.aws_s3_bucket.this
}
moved {
  from = aws_s3_bucket_public_access_block.logs
  to   = module.logs_bucket.aws_s3_bucket_public_access_block.this
}
moved {
  from = aws_s3_bucket_server_side_encryption_configuration.logs
  to   = module.logs_bucket.aws_s3_bucket_server_side_encryption_configuration.this
}
moved {
  from = aws_s3_bucket_versioning.logs
  to   = module.logs_bucket.aws_s3_bucket_versioning.this
}
moved {
  from = aws_s3_bucket_policy.logs
  to   = module.logs_bucket.aws_s3_bucket_policy.this
}
moved {
  from = aws_s3_bucket_lifecycle_configuration.logs
  to   = module.logs_bucket.aws_s3_bucket_lifecycle_configuration.this
}

# --- novacorp-customer-data ---
moved {
  from = aws_s3_bucket.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket.this
}
moved {
  from = aws_s3_bucket_public_access_block.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_public_access_block.this
}
moved {
  from = aws_s3_bucket_server_side_encryption_configuration.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_server_side_encryption_configuration.this
}
moved {
  from = aws_s3_bucket_versioning.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_versioning.this
}
moved {
  from = aws_s3_bucket_policy.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_policy.this
}
moved {
  from = aws_s3_bucket_lifecycle_configuration.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_lifecycle_configuration.this
}
moved {
  from = aws_s3_bucket_logging.customer_data
  to   = module.customer_data_bucket.aws_s3_bucket_logging.this[0]
}
