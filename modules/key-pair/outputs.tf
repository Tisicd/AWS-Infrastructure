output "key_pair_id" {
  description = "ID of the key pair"
  value       = var.create_key_pair ? aws_key_pair.this[0].key_pair_id : data.aws_key_pair.existing[0].key_pair_id
}

output "key_pair_name" {
  description = "Name of the key pair"
  value       = var.key_pair_name
}

output "key_pair_arn" {
  description = "ARN of the key pair"
  value       = var.create_key_pair ? aws_key_pair.this[0].arn : data.aws_key_pair.existing[0].arn
}

output "private_key_pem" {
  description = "Private key in PEM format (only if create_key_pair is true and save_private_key is false - for manual retrieval)"
  value       = var.create_key_pair && !var.save_private_key ? tls_private_key.key_pair[0].private_key_pem : null
  sensitive   = true
}

output "public_key_openssh" {
  description = "Public key in OpenSSH format"
  value       = var.create_key_pair ? tls_private_key.key_pair[0].public_key_openssh : data.aws_key_pair.existing[0].public_key
}
