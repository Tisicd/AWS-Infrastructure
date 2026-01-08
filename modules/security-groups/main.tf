# =============================================================================
# Security Groups Module - AWS Academy Compatible
# =============================================================================

# Bastion Security Group
resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Security group for Bastion Host (Jump Box)"
  vpc_id      = var.vpc_id

  # SSH from your IP only
  # NOTE: AWS Academy may require 0.0.0.0/0 due to NAT/Proxy behavior
  # In production, restrict this to specific IP ranges
  ingress {
    description = "SSH from Internet (AWS Academy compatibility)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Changed from var.your_ip_cidr for AWS Academy
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion-sg"
    }
  )
}

# Kong API Gateway Security Group
resource "aws_security_group" "kong" {
  count = var.enable_kong ? 1 : 0

  name        = "${var.project_name}-${var.environment}-kong-sg"
  description = "Security group for Kong API Gateway"
  vpc_id      = var.vpc_id

  # HTTP from anywhere (public API)
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS from anywhere (public API)
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Kong Admin API from your IP only
  ingress {
    description = "Kong Admin API from your IP"
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Kong Admin API SSL from your IP only
  ingress {
    description = "Kong Admin API SSL from your IP"
    from_port   = 8444
    to_port     = 8444
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # SSH from Bastion only
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-sg"
    }
  )
}

# Microservices Security Group
resource "aws_security_group" "microservices" {
  count = var.enable_microservices ? 1 : 0

  name        = "${var.project_name}-${var.environment}-microservices-sg"
  description = "Security group for Microservices"
  vpc_id      = var.vpc_id

  # HTTP traffic from Kong
  ingress {
    description     = "HTTP from Kong"
    from_port       = 3000
    to_port         = 3100
    protocol        = "tcp"
    security_groups = var.enable_kong ? [aws_security_group.kong[0].id] : []
  }

  # SSH from Bastion only
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-microservices-sg"
    }
  )
}

# Database Security Group
resource "aws_security_group" "database" {
  count = var.enable_database ? 1 : 0

  name        = "${var.project_name}-${var.environment}-database-sg"
  description = "Security group for Database Server"
  vpc_id      = var.vpc_id

  # PostgreSQL from Microservices
  ingress {
    description     = "PostgreSQL from Microservices"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # PostgreSQL from Kong (for Kong database)
  ingress {
    description     = "PostgreSQL from Kong"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.enable_kong ? [aws_security_group.kong[0].id] : []
  }

  # Redis from Microservices
  ingress {
    description     = "Redis from Microservices"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # TimescaleDB from Microservices
  ingress {
    description     = "TimescaleDB from Microservices"
    from_port       = 5433
    to_port         = 5433
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # SSH from Bastion only
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database-sg"
    }
  )
}

# =============================================================================
# Outputs
# =============================================================================

output "bastion_security_group_id" {
  description = "ID of Bastion security group"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
}

output "kong_security_group_id" {
  description = "ID of Kong security group"
  value       = var.enable_kong ? aws_security_group.kong[0].id : null
}

output "microservices_security_group_id" {
  description = "ID of Microservices security group"
  value       = var.enable_microservices ? aws_security_group.microservices[0].id : null
}

output "database_security_group_id" {
  description = "ID of Database security group"
  value       = var.enable_database ? aws_security_group.database[0].id : null
}
