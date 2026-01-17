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

  # HTTP/HTTPS to Microservices in service accounts (via VPC CIDR)
  dynamic "egress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "HTTP to service account microservices"
      from_port   = 3001
      to_port     = 3009
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }

  # SSH from Bastion (preferred method)
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  # SSH from Internet (for AWS Console connection - use Bastion in production)
  # NOTE: This is less secure but required for AWS Console "Connect" button
  ingress {
    description = "SSH from Internet (for AWS Console - use Bastion in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # WARNING: Restrict to your IP in production
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

  # HTTP traffic from Kong (hub account only)
  ingress {
    description     = "HTTP from Kong (Hub Account)"
    from_port       = 3000
    to_port         = 3100
    protocol        = "tcp"
    security_groups = var.enable_kong ? [aws_security_group.kong[0].id] : []
  }

  # Inter-service communication between microservices (ports 3001-3009)
  # Allow from same security group (same account)
  ingress {
    description = "Inter-service communication (same account)"
    from_port   = 3001
    to_port     = 3009
    protocol    = "tcp"
    self        = true  # Permite tráfico desde el mismo security group
  }

  # Inter-service communication from other accounts via VPC CIDR blocks
  # For hub account: allow from service account VPCs
  dynamic "ingress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "Inter-service communication from service account VPC"
      from_port   = 3001
      to_port     = 3009
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # For service accounts: allow from hub account VPC
  dynamic "ingress" {
    for_each = var.account_type == "service" && var.hub_vpc_cidr != "" ? [var.hub_vpc_cidr] : []
    content {
      description = "Inter-service communication from hub account VPC"
      from_port   = 3001
      to_port     = 3009
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # SSH from Bastion (preferred method)
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  # SSH from Internet (for AWS Console connection - only if not in private subnet)
  # NOTE: This is less secure but required for AWS Console "Connect" button
  # In production, remove this and always use Bastion
  ingress {
    description = "SSH from Internet (for AWS Console - use Bastion in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # WARNING: Restrict to your IP in production
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

  # PostgreSQL from Microservices (same account)
  ingress {
    description     = "PostgreSQL from Microservices (same account)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # PostgreSQL from Microservices (service accounts via VPC CIDR)
  dynamic "ingress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "PostgreSQL from service account microservices"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # PostgreSQL from Kong (for Kong database)
  ingress {
    description     = "PostgreSQL from Kong"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.enable_kong ? [aws_security_group.kong[0].id] : []
  }

  # Redis from Microservices (same account)
  ingress {
    description     = "Redis from Microservices (same account)"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # Redis from Microservices (service accounts via VPC CIDR)
  dynamic "ingress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "Redis from service account microservices"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # TimescaleDB from Microservices (same account)
  ingress {
    description     = "TimescaleDB from Microservices (same account)"
    from_port       = 5433
    to_port         = 5433
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # TimescaleDB from Microservices (service accounts via VPC CIDR)
  dynamic "ingress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "TimescaleDB from service account microservices"
      from_port   = 5433
      to_port     = 5433
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # SSH from Bastion (preferred method)
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.enable_bastion ? [aws_security_group.bastion[0].id] : []
  }

  # SSH from Internet (for AWS Console connection - use Bastion in production)
  # NOTE: This is less secure but required for AWS Console "Connect" button
  ingress {
    description = "SSH from Internet (for AWS Console - use Bastion in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # WARNING: Restrict to your IP in production
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

# Load Balancer Security Group
resource "aws_security_group" "load_balancer" {
  count = var.enable_load_balancer ? 1 : 0

  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # HTTP from Internet
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS from Internet
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow traffic to microservices
  egress {
    description     = "HTTP/HTTPS to Microservices"
    from_port       = 3000
    to_port         = 3100
    protocol        = "tcp"
    security_groups = var.enable_microservices ? [aws_security_group.microservices[0].id] : []
  }

  # Allow traffic to service account microservices via VPC CIDR
  dynamic "egress" {
    for_each = var.account_type == "hub" && length(var.service_account_vpc_cidrs) > 0 ? var.service_account_vpc_cidrs : []
    content {
      description = "HTTP/HTTPS to service account microservices"
      from_port   = 3000
      to_port     = 3100
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alb-sg"
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

output "load_balancer_security_group_id" {
  description = "ID of Load Balancer security group"
  value       = var.enable_load_balancer ? aws_security_group.load_balancer[0].id : null
}
