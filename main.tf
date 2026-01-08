# =============================================================================
# AWS Academic Platform - Terraform Main Configuration (AWS Academy Compatible)
# =============================================================================
# Optimized for AWS Academy Learner Labs with EC2-based architecture
# No managed services (ECS, RDS, ElastiCache) - Using self-hosted on EC2
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for state storage
  # For AWS Academy, use local state or S3 if available
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "academic-platform/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.common_tags,
      {
        Environment = var.environment
        ManagedBy   = "Terraform"
        Project     = "Academic-Platform"
        Academy     = "AWS-Learner-Lab"
      }
    )
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get existing VPC (AWS Academy provides pre-created VPC)
data "aws_vpc" "existing" {
  id = var.vpc_id
}

# Get existing subnets
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Availability zones (limit to 2 for cost optimization)
  azs = slice(data.aws_availability_zones.available.names, 0, min(2, length(data.aws_availability_zones.available.names)))
  
  # Subnet IDs
  public_subnet_ids  = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : data.aws_subnets.public.ids
  private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : data.aws_subnets.private.ids
  
  # EIP limits for AWS Academy accounts
  max_eips_allowed = var.max_elastic_ips
  
  # Calculate EIP usage: Kong (1) + NAT (if enabled) + Bastion (1) + Database (optional)
  eips_used = (var.enable_kong ? 1 : 0) + (var.enable_nat_gateway ? var.nat_gateway_count : 0) + (var.enable_bastion ? 1 : 0) + (var.database_needs_eip ? 1 : 0)
  
  # Validation
  eips_within_limit = local.eips_used <= local.max_eips_allowed

  # Common tags
  common_tags = merge(
    var.common_tags,
    {
      Terraform   = "true"
      Environment = var.environment
      Account     = data.aws_caller_identity.current.account_id
    }
  )
}

# =============================================================================
# EIP Limit Validation
# =============================================================================

resource "null_resource" "eip_validation" {
  triggers = {
    eips_used        = local.eips_used
    eips_limit       = local.max_eips_allowed
    validation_check = local.eips_within_limit
  }

  provisioner "local-exec" {
    command = local.eips_within_limit ? "echo 'EIP validation passed: Using ${local.eips_used}/${local.max_eips_allowed} EIPs'" : "echo 'ERROR: EIP limit exceeded! Using ${local.eips_used} but limit is ${local.max_eips_allowed}' && exit 1"
  }
}

# =============================================================================
# NAT Gateway (Optional for private subnets)
# =============================================================================

module "nat_gateway" {
  count  = var.enable_nat_gateway ? 1 : 0
  source = "./modules/nat-gateway"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = var.vpc_id

  public_subnet_ids  = local.public_subnet_ids
  private_subnet_ids = local.private_subnet_ids
  nat_gateway_count  = var.nat_gateway_count
  single_nat_gateway = var.single_nat_gateway

  tags = local.common_tags
}

# =============================================================================
# Security Groups Module
# =============================================================================

module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = var.vpc_id

  # CIDR blocks for access control
  allowed_cidr_blocks = var.allowed_cidr_blocks
  your_ip_cidr        = var.your_ip_cidr

  # Enable specific security groups
  enable_kong         = var.enable_kong
  enable_bastion      = var.enable_bastion
  enable_database     = var.enable_database
  enable_microservices = var.enable_microservices

  tags = local.common_tags
}

# =============================================================================
# Bastion Host Module (Jump Box)
# =============================================================================

module "bastion_host" {
  count  = var.enable_bastion ? 1 : 0
  source = "./modules/bastion-host"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id           = var.vpc_id
  subnet_id        = local.public_subnet_ids[0]
  security_group_id = module.security_groups.bastion_security_group_id

  # Instance configuration
  instance_type = var.bastion_instance_type
  ami_id        = data.aws_ami.amazon_linux_2023.id
  key_name      = var.key_pair_name

  # EIP configuration
  allocate_eip = true

  tags = local.common_tags
}

# =============================================================================
# Database Server Module (PostgreSQL + Redis + TimescaleDB)
# =============================================================================

module "database_server" {
  count  = var.enable_database ? 1 : 0
  source = "./modules/ec2-database"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id            = var.vpc_id
  subnet_id         = var.database_in_private_subnet ? local.private_subnet_ids[0] : local.public_subnet_ids[0]
  security_group_id = module.security_groups.database_security_group_id

  # Instance configuration
  instance_type = var.database_instance_type
  ami_id        = data.aws_ami.amazon_linux_2023.id
  key_name      = var.key_pair_name

  # Storage configuration
  root_volume_size = var.database_root_volume_size
  data_volume_size = var.database_data_volume_size
  data_volume_type = var.database_data_volume_type

  # EIP configuration (optional, for external backups)
  allocate_eip = var.database_needs_eip

  # Database configuration
  postgres_version  = var.postgres_version
  redis_version     = var.redis_version
  enable_timescaledb = var.enable_timescaledb

  # Backup configuration
  enable_automated_backups = var.database_enable_backups
  backup_retention_days    = var.database_backup_retention_days
  backup_s3_bucket        = var.database_backup_s3_bucket

  tags = local.common_tags

  depends_on = [module.bastion_host]
}

# =============================================================================
# Kong API Gateway Module
# =============================================================================

module "kong_gateway" {
  count  = var.enable_kong ? 1 : 0
  source = "./modules/ec2-kong"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id             = var.vpc_id
  subnet_ids         = local.public_subnet_ids
  security_group_id  = module.security_groups.kong_security_group_id

  # Instance configuration
  instance_type = var.kong_instance_type
  ami_id        = data.aws_ami.amazon_linux_2023.id
  key_name      = var.key_pair_name

  # Kong configuration
  kong_version       = var.kong_version
  kong_database_host = var.enable_database ? module.database_server[0].private_ip : ""
  kong_database_port = 5432
  kong_database_name = var.kong_database_name
  kong_admin_api_uri = var.kong_admin_api_uri

  # High Availability
  instance_count       = var.kong_instance_count
  enable_health_check  = true
  health_check_path    = "/status"

  # EIP configuration
  allocate_eip_per_instance = true

  tags = local.common_tags

  depends_on = [module.database_server]
}

# =============================================================================
# Microservices Auto Scaling Group Module
# =============================================================================

module "microservices_asg" {
  count  = var.enable_microservices ? 1 : 0
  source = "./modules/asg-microservices"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id             = var.vpc_id
  subnet_ids         = var.microservices_in_private_subnet ? local.private_subnet_ids : local.public_subnet_ids
  security_group_id  = module.security_groups.microservices_security_group_id

  # Launch Template configuration
  ami_id        = data.aws_ami.amazon_linux_2023.id
  instance_type = var.microservices_instance_type
  key_name      = var.key_pair_name

  # Auto Scaling configuration
  min_size         = var.microservices_min_size
  max_size         = var.microservices_max_size
  desired_capacity = var.microservices_desired_capacity

  # Scaling policies
  enable_scaling_policies     = var.microservices_enable_scaling
  scale_up_cpu_threshold      = var.microservices_scale_up_cpu
  scale_down_cpu_threshold    = var.microservices_scale_down_cpu
  scale_up_adjustment         = 1
  scale_down_adjustment       = -1

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Services configuration
  services = var.microservices_services

  # Environment variables
  database_host = var.enable_database ? module.database_server[0].private_ip : ""
  redis_host    = var.enable_database ? module.database_server[0].private_ip : ""
  kong_endpoint = var.enable_kong ? module.kong_gateway[0].kong_proxy_endpoint : ""

  # Docker registry
  docker_registry = var.docker_registry
  docker_registry_username = var.docker_registry_username
  docker_registry_password = var.docker_registry_password

  tags = local.common_tags

  depends_on = [
    module.database_server,
    module.kong_gateway
  ]
}

# =============================================================================
# CloudWatch Monitoring Module
# =============================================================================

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  # SNS topic for alerts
  create_sns_topic    = var.create_sns_topic
  sns_email_endpoints = var.monitoring_email_endpoints

  # CloudWatch Log Groups
  log_retention_days = var.cloudwatch_log_retention_days

  # Alarms configuration
  enable_alarms = var.enable_cloudwatch_alarms

  # EC2 instance IDs for monitoring
  kong_instance_ids          = var.enable_kong ? module.kong_gateway[0].instance_ids : []
  database_instance_ids      = var.enable_database ? [module.database_server[0].instance_id] : []
  microservices_asg_name     = var.enable_microservices ? module.microservices_asg[0].asg_name : ""

  tags = local.common_tags
}

# =============================================================================
# Outputs
# =============================================================================

# EIP Usage
output "eips_used_count" {
  description = "Number of Elastic IPs used by this deployment"
  value       = local.eips_used
}

output "eips_remaining" {
  description = "Remaining Elastic IPs available in account"
  value       = local.max_eips_allowed - local.eips_used
}

output "eips_within_limit" {
  description = "Whether EIP usage is within account limits"
  value       = local.eips_within_limit
}

# Network outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = local.private_subnet_ids
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = var.enable_nat_gateway ? module.nat_gateway[0].nat_gateway_ips : []
}

# Bastion outputs
output "bastion_public_ip" {
  description = "Public IP of Bastion Host"
  value       = var.enable_bastion ? module.bastion_host[0].public_ip : null
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion"
  value       = var.enable_bastion ? "ssh -i ${var.key_pair_name}.pem ec2-user@${module.bastion_host[0].public_ip}" : null
}

# Database outputs
output "database_private_ip" {
  description = "Private IP of Database Server"
  value       = var.enable_database ? module.database_server[0].private_ip : null
  sensitive   = true
}

output "database_public_ip" {
  description = "Public IP of Database Server (if EIP allocated)"
  value       = var.enable_database && var.database_needs_eip ? module.database_server[0].public_ip : null
  sensitive   = true
}

output "postgres_endpoint" {
  description = "PostgreSQL connection endpoint"
  value       = var.enable_database ? "${module.database_server[0].private_ip}:5432" : null
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis connection endpoint"
  value       = var.enable_database ? "${module.database_server[0].private_ip}:6379" : null
  sensitive   = true
}

# Kong outputs
output "kong_public_ips" {
  description = "Public IPs of Kong API Gateway instances"
  value       = var.enable_kong ? module.kong_gateway[0].public_ips : []
}

output "kong_proxy_endpoint" {
  description = "Kong Proxy endpoint (for API requests)"
  value       = var.enable_kong ? module.kong_gateway[0].kong_proxy_endpoint : null
}

output "kong_admin_endpoint" {
  description = "Kong Admin API endpoint"
  value       = var.enable_kong ? module.kong_gateway[0].kong_admin_endpoint : null
  sensitive   = true
}

# Microservices outputs
output "microservices_asg_name" {
  description = "Name of Microservices Auto Scaling Group"
  value       = var.enable_microservices ? module.microservices_asg[0].asg_name : null
}

output "microservices_instance_count" {
  description = "Current number of microservices instances"
  value       = var.enable_microservices ? module.microservices_asg[0].current_instance_count : 0
}

# Monitoring outputs
output "sns_topic_arn" {
  description = "ARN of SNS topic for monitoring alerts"
  value       = var.create_sns_topic ? module.monitoring.sns_topic_arn : null
}

# Summary output
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment           = var.environment
    vpc_id                = var.vpc_id
    bastion_enabled       = var.enable_bastion
    kong_enabled          = var.enable_kong
    database_enabled      = var.enable_database
    microservices_enabled = var.enable_microservices
    eips_used             = local.eips_used
    eips_limit            = local.max_eips_allowed
    cost_estimate_monthly = var.environment == "dev" ? "$60-80" : var.environment == "qa" ? "$120-160" : "$200-300"
  }
}
