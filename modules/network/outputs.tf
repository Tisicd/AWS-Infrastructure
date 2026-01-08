output "vpc_id" {
  description = "ID of the VPC (created or existing)"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = var.use_existing_vpc ? var.public_subnet_ids : aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.use_existing_vpc ? null : aws_internet_gateway.main[0].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}




