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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
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

# Get subnet details to filter by availability zone
# This allows us to exclude subnets in AZs that don't support certain instance types
data "aws_subnet" "subnet_details" {
  for_each = toset(concat(
    length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : data.aws_subnets.public.ids,
    length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : data.aws_subnets.private.ids
  ))
  id = each.value
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
  
  # Account type flags
  is_hub_account    = var.account_type == "hub"
  is_service_account = var.account_type == "service"
  
  # Current account ID
  current_account_id = var.account_id != "" ? var.account_id : data.aws_caller_identity.current.account_id
  
  # Availability zones (limit to 2 for cost optimization)
  azs = slice(data.aws_availability_zones.available.names, 0, min(2, length(data.aws_availability_zones.available.names)))
  
  # Exclude incompatible AZs (e.g., us-east-1e doesn't support t3.medium)
  # Common incompatible AZs for t3.medium: us-east-1e
  incompatible_azs = ["us-east-1e"]
  
  # Base subnet lists
  base_public_subnet_ids  = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : data.aws_subnets.public.ids
  base_private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : data.aws_subnets.private.ids
  
  # Filter subnets to exclude incompatible AZs for microservices ASG
  # This ensures t3.medium instances can be launched successfully
  compatible_public_subnets = [
    for subnet_id in local.base_public_subnet_ids : subnet_id
    if !contains(local.incompatible_azs, try(data.aws_subnet.subnet_details[subnet_id].availability_zone, ""))
  ]
  
  compatible_private_subnets = [
    for subnet_id in local.base_private_subnet_ids : subnet_id
    if !contains(local.incompatible_azs, try(data.aws_subnet.subnet_details[subnet_id].availability_zone, ""))
  ]
  
  # Use filtered subnets for microservices ASG, fallback to base subnets if filtered list is empty
  public_subnet_ids  = length(local.compatible_public_subnets) > 0 ? local.compatible_public_subnets : local.base_public_subnet_ids
  private_subnet_ids = length(local.compatible_private_subnets) > 0 ? local.compatible_private_subnets : local.base_private_subnet_ids
  
  # EIP limits for AWS Academy accounts
  max_eips_allowed = var.max_elastic_ips
  
  # Calculate EIP usage based on account type:
  # Hub account: Kong (1) + NAT (if enabled) + Bastion (1) + Database (optional)
  # Service account: Only microservices (no EIPs needed)
  eips_used = local.is_hub_account ? (
    (var.enable_kong && local.is_hub_account ? 1 : 0) + 
    (var.enable_nat_gateway && local.is_hub_account ? var.nat_gateway_count : 0) + 
    (var.enable_bastion && local.is_hub_account ? 1 : 0) + 
    (var.database_needs_eip && local.is_hub_account ? 1 : 0)
  ) : 0
  
  # Validation
  eips_within_limit = local.eips_used <= local.max_eips_allowed

  # Common tags
  common_tags = merge(
    var.common_tags,
    {
      Terraform    = "true"
      Environment  = var.environment
      Account      = local.current_account_id
      AccountType  = var.account_type
    }
  )
  
  # Validation: Service accounts must have hub_account_id
  # This will be checked via a validation block in variables.tf
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
# NAT Gateway (Optional for private subnets) - Hub Account Only
# =============================================================================

module "nat_gateway" {
  count  = var.enable_nat_gateway && local.is_hub_account ? 1 : 0
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
# Key Pair Module
# =============================================================================

module "key_pair" {
  source = "./modules/key-pair"

  key_pair_name    = "${var.key_pair_name}-${var.environment}"
  create_key_pair  = var.create_key_pair
  save_private_key = var.save_key_pair_locally
  private_key_path = var.save_key_pair_locally ? "${path.module}/deployments/${var.account_type == "hub" ? "hub-account" : "service-account"}/${var.key_pair_name}-${var.environment}.pem" : ""

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

  # Enable specific security groups based on account type
  enable_kong          = var.enable_kong && local.is_hub_account
  enable_bastion       = var.enable_bastion && local.is_hub_account
  enable_database      = var.enable_database && local.is_hub_account
  enable_microservices = var.enable_microservices
  enable_load_balancer = var.microservices_enable_load_balancer && var.enable_microservices

  # Cross-account configuration
  account_type                      = var.account_type
  hub_account_id                    = var.hub_account_id
  cross_account_security_group_ids  = var.cross_account_security_group_ids
  hub_vpc_cidr                      = var.hub_vpc_cidr
  service_account_vpc_cidrs         = var.service_account_vpc_cidrs

  tags = local.common_tags
}

# =============================================================================
# Bastion Host Module (Jump Box) - Hub Account Only
# =============================================================================

# Data source to get subnet availability zone for bastion
data "aws_subnet" "bastion_subnet" {
  count = var.enable_bastion && local.is_hub_account && length(local.public_subnet_ids) > 0 ? 1 : 0
  id    = local.public_subnet_ids[0]
}

module "bastion_host" {
  count  = var.enable_bastion && local.is_hub_account ? 1 : 0
  source = "./modules/bastion-host"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id           = var.vpc_id
  subnet_id        = local.public_subnet_ids[0]
  security_group_id = module.security_groups.bastion_security_group_id

  # Instance configuration
  instance_type     = var.bastion_instance_type
  ami_id            = data.aws_ami.amazon_linux_2023.id
  key_name = module.key_pair.key_pair_name
  root_volume_size  = var.bastion_root_volume_size

  # EIP configuration
  allocate_eip = true

  # Auto Scaling Group for auto-recovery (enabled by default)
  enable_asg = true

  tags = local.common_tags
}

# =============================================================================
# Database Server Module (PostgreSQL + Redis + TimescaleDB) - Hub Account Only
# =============================================================================

# Data source to get subnet availability zone for database
data "aws_subnet" "database_subnet" {
  count = var.enable_database && local.is_hub_account ? 1 : 0
  id    = var.database_in_private_subnet ? (length(local.private_subnet_ids) > 0 ? local.private_subnet_ids[0] : local.public_subnet_ids[0]) : local.public_subnet_ids[0]
}

module "database_server" {
  count  = var.enable_database && local.is_hub_account ? 1 : 0
  source = "./modules/ec2-database"

  project_name = var.project_name
  environment  = var.environment

  # Network configuration
  vpc_id            = var.vpc_id
  subnet_id         = var.database_in_private_subnet ? (length(local.private_subnet_ids) > 0 ? local.private_subnet_ids[0] : local.public_subnet_ids[0]) : local.public_subnet_ids[0]
  security_group_id = module.security_groups.database_security_group_id
  subnet_availability_zone = length(data.aws_subnet.database_subnet) > 0 ? data.aws_subnet.database_subnet[0].availability_zone : ""

  # Instance configuration
  instance_type = var.database_instance_type
  ami_id        = data.aws_ami.amazon_linux_2023.id
  key_name      = module.key_pair.key_pair_name

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
  enable_mongodb     = var.enable_mongodb
  mongodb_version    = var.mongodb_version

  # Backup configuration
  enable_automated_backups = var.database_enable_backups
  backup_retention_days    = var.database_backup_retention_days
  backup_s3_bucket        = var.database_backup_s3_bucket

  # Auto Scaling Group for auto-recovery (enabled by default)
  enable_asg = true

  tags = local.common_tags

  depends_on = [module.bastion_host]
}

# =============================================================================
# Kong API Gateway Module - Hub Account Only
# =============================================================================

module "kong_gateway" {
  count  = var.enable_kong && local.is_hub_account ? 1 : 0
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
  key_name      = module.key_pair.key_pair_name

  # Kong configuration
  kong_version       = var.kong_version
  kong_database_host = var.enable_database && local.is_hub_account && length(module.database_server) > 0 && module.database_server[0].private_ip != null ? module.database_server[0].private_ip : "localhost"
  kong_database_port = 5432
  kong_database_name = var.kong_database_name
  kong_admin_api_uri = var.kong_admin_api_uri
  health_check_path  = "/status"

  # Auto Scaling Group configuration
  enable_asg               = var.kong_enable_asg
  min_size                 = var.kong_min_size
  max_size                 = var.kong_max_size
  desired_capacity         = var.kong_desired_capacity
  health_check_grace_period = var.kong_health_check_grace_period

  # Instance count (only used when ASG is disabled)
  instance_count = var.kong_enable_asg ? 1 : var.kong_instance_count

  # Load Balancer configuration
  load_balancer_internal            = var.kong_load_balancer_internal
  load_balancer_subnet_ids          = var.kong_load_balancer_internal ? local.private_subnet_ids : local.public_subnet_ids
  load_balancer_security_group_ids  = [module.security_groups.kong_security_group_id]
  load_balancer_listener_port       = 80
  load_balancer_listener_protocol   = "HTTP"
  target_group_port                 = 8000
  target_group_protocol             = "HTTP"
  health_check_matcher              = "200"

  # EIP configuration: Always allocate EIP for Kong in hub account
  # When ASG is enabled: EIP is created and associated via user-data script
  # When ASG is disabled: EIP is created and associated via aws_eip_association
  allocate_eip_per_instance = var.kong_enable_asg ? true : true  # Always allocate EIP for Kong

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
  key_name      = module.key_pair.key_pair_name

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
  # For service accounts, these should be provided via variables pointing to hub account resources
  database_host = var.enable_database && local.is_hub_account && length(module.database_server) > 0 ? module.database_server[0].private_ip : var.database_host_override
  redis_host    = var.enable_database && local.is_hub_account && length(module.database_server) > 0 ? module.database_server[0].private_ip : var.redis_host_override
  kong_endpoint = var.enable_kong && local.is_hub_account && length(module.kong_gateway) > 0 ? module.kong_gateway[0].kong_proxy_endpoint : var.kong_endpoint_override

  # Docker registry
  docker_registry = var.docker_registry
  docker_registry_username = var.docker_registry_username
  docker_registry_password = var.docker_registry_password

  # Load Balancer configuration
  enable_load_balancer              = var.microservices_enable_load_balancer
  load_balancer_internal            = var.microservices_load_balancer_internal
  load_balancer_subnet_ids           = var.microservices_load_balancer_internal ? local.private_subnet_ids : local.public_subnet_ids
  load_balancer_security_group_ids   = var.microservices_enable_load_balancer ? [module.security_groups.load_balancer_security_group_id] : []
  load_balancer_listener_port       = 80
  load_balancer_listener_protocol   = "HTTP"
  target_group_port                  = 3000
  target_group_protocol              = "HTTP"
  health_check_path                  = "/health"
  health_check_matcher               = "200"

  # Elastic IP configuration
  enable_elastic_ips = var.microservices_enable_elastic_ips

  # Auto Recovery configuration
  enable_auto_recovery = true  # Always enable auto-recovery for microservices

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
  count = local.is_hub_account ? 1 : 0
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  # SNS topic for alerts (solo en hub account)
  create_sns_topic    = var.create_sns_topic
  sns_email_endpoints = var.monitoring_email_endpoints

  # CloudWatch Log Groups
  log_retention_days = var.cloudwatch_log_retention_days

  # Alarms configuration
  enable_alarms = var.enable_cloudwatch_alarms

  # EC2 instance IDs for monitoring
  kong_instance_ids          = var.enable_kong && local.is_hub_account && length(module.kong_gateway) > 0 ? module.kong_gateway[0].instance_ids : []
  database_instance_ids      = var.enable_database && local.is_hub_account && length(module.database_server) > 0 ? [module.database_server[0].instance_id] : []
  microservices_asg_name     = var.enable_microservices && length(module.microservices_asg) > 0 ? module.microservices_asg[0].asg_name : ""

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
  value       = var.enable_bastion && local.is_hub_account && length(module.bastion_host) > 0 ? module.bastion_host[0].public_ip : null
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion"
  value       = var.enable_bastion && local.is_hub_account && length(module.bastion_host) > 0 ? "ssh -i ${module.key_pair.key_pair_name}.pem ec2-user@${module.bastion_host[0].public_ip}" : null
}

# Database outputs
output "database_private_ip" {
  description = "Private IP of Database Server"
  value       = var.enable_database && local.is_hub_account && length(module.database_server) > 0 ? module.database_server[0].private_ip : null
  sensitive   = true
}

output "database_public_ip" {
  description = "Public IP of Database Server (if EIP allocated)"
  value       = var.enable_database && local.is_hub_account && var.database_needs_eip && length(module.database_server) > 0 ? module.database_server[0].public_ip : null
  sensitive   = true
}

output "postgres_endpoint" {
  description = "PostgreSQL connection endpoint"
  value       = var.enable_database && local.is_hub_account && length(module.database_server) > 0 && module.database_server[0].private_ip != null ? "${module.database_server[0].private_ip}:5432" : null
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis connection endpoint"
  value       = var.enable_database && local.is_hub_account && length(module.database_server) > 0 && module.database_server[0].private_ip != null ? "${module.database_server[0].private_ip}:6379" : null
  sensitive   = true
}

output "mongodb_endpoint" {
  description = "MongoDB connection endpoint"
  value       = var.enable_database && local.is_hub_account && var.enable_mongodb && length(module.database_server) > 0 ? module.database_server[0].mongodb_endpoint : null
  sensitive   = true
}

# Kong outputs
output "kong_public_ips" {
  description = "Public IPs of Kong API Gateway instances"
  value       = var.enable_kong && local.is_hub_account && length(module.kong_gateway) > 0 ? module.kong_gateway[0].public_ips : []
}

output "kong_proxy_endpoint" {
  description = "Kong Proxy endpoint (for API requests)"
  value       = var.enable_kong && local.is_hub_account && length(module.kong_gateway) > 0 ? module.kong_gateway[0].kong_proxy_endpoint : null
}

output "kong_admin_endpoint" {
  description = "Kong Admin API endpoint"
  value       = var.enable_kong && local.is_hub_account && length(module.kong_gateway) > 0 ? module.kong_gateway[0].kong_admin_endpoint : null
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

output "microservices_load_balancer_dns" {
  description = "DNS name of the Application Load Balancer for microservices"
  value       = var.enable_microservices && var.microservices_enable_load_balancer ? module.microservices_asg[0].load_balancer_dns_name : null
}

output "microservices_elastic_ips" {
  description = "Elastic IPs allocated for microservices (one per service)"
  value       = var.enable_microservices && var.microservices_enable_elastic_ips ? module.microservices_asg[0].elastic_ips : {}
}

# Monitoring outputs
output "sns_topic_arn" {
  description = "ARN of SNS topic for monitoring alerts"
  value       = local.is_hub_account && var.create_sns_topic && length(module.monitoring) > 0 ? module.monitoring[0].sns_topic_arn : null
}

# Multi-Account outputs
output "current_account_id" {
  description = "Current AWS Account ID"
  value       = local.current_account_id
}

output "account_type" {
  description = "Type of AWS account (hub or service)"
  value       = var.account_type
}

output "vpc_cidr_block" {
  description = "CIDR block of the current VPC (useful for cross-account configuration)"
  value       = data.aws_vpc.existing.cidr_block
}

# Summary output
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment           = var.environment
    account_type          = var.account_type
    account_id            = local.current_account_id
    vpc_id                = var.vpc_id
    vpc_cidr              = data.aws_vpc.existing.cidr_block
    bastion_enabled       = var.enable_bastion && local.is_hub_account
    kong_enabled          = var.enable_kong && local.is_hub_account
    database_enabled      = var.enable_database && local.is_hub_account
    microservices_enabled = var.enable_microservices
    eips_used             = local.eips_used
    eips_limit            = local.max_eips_allowed
    cost_estimate_monthly = var.environment == "dev" ? "$60-80" : var.environment == "qa" ? "$120-160" : "$200-300"
  }
}
