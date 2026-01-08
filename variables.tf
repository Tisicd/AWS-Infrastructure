# =============================================================================
# AWS Academic Platform - Terraform Variables (AWS Academy Compatible)
# =============================================================================

# =============================================================================
# General Configuration
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "academic-platform"
}

variable "environment" {
  description = "Environment name (dev, qa, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "Environment must be dev, qa, or prod."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AWS Academy Constraints
# =============================================================================

variable "max_elastic_ips" {
  description = "Maximum number of Elastic IPs allowed (AWS Academy default: 5)"
  type        = number
  default     = 5
  validation {
    condition     = var.max_elastic_ips > 0 && var.max_elastic_ips <= 5
    error_message = "max_elastic_ips must be between 1 and 5 for AWS Academy."
  }
}

# =============================================================================
# VPC Configuration (AWS Academy Pre-created VPC)
# =============================================================================

variable "vpc_id" {
  description = "ID of existing VPC (required for AWS Academy)"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of existing public subnets"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "IDs of existing private subnets"
  type        = list(string)
  default     = []
}

# =============================================================================
# NAT Gateway Configuration
# =============================================================================

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = false  # Disabled by default to save EIPs
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways (limited by EIP availability)"
  type        = number
  default     = 1
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = true
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access public services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "your_ip_cidr" {
  description = "Your IP address in CIDR format (for SSH and Kong Admin access)"
  type        = string
  default     = "0.0.0.0/0"  # CHANGE THIS TO YOUR IP!
}

variable "key_pair_name" {
  description = "Name of EC2 Key Pair for SSH access"
  type        = string
}

# =============================================================================
# Feature Toggles
# =============================================================================

variable "enable_bastion" {
  description = "Enable Bastion Host (Jump Box)"
  type        = bool
  default     = true
}

variable "enable_database" {
  description = "Enable Database Server (PostgreSQL + Redis)"
  type        = bool
  default     = true
}

variable "enable_kong" {
  description = "Enable Kong API Gateway"
  type        = bool
  default     = true
}

variable "enable_microservices" {
  description = "Enable Microservices Auto Scaling Group"
  type        = bool
  default     = true
}

# =============================================================================
# Bastion Host Configuration
# =============================================================================

variable "bastion_instance_type" {
  description = "Instance type for Bastion Host"
  type        = string
  default     = "t3.micro"
}

# =============================================================================
# Database Server Configuration
# =============================================================================

variable "database_instance_type" {
  description = "Instance type for Database Server"
  type        = string
  default     = "t3.medium"
}

variable "database_in_private_subnet" {
  description = "Place database in private subnet"
  type        = bool
  default     = false  # In public for AWS Academy simplicity
}

variable "database_needs_eip" {
  description = "Allocate EIP for database (for external backups)"
  type        = bool
  default     = false
}

variable "database_root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

variable "database_data_volume_size" {
  description = "Size of data volume in GB"
  type        = number
  default     = 50
}

variable "database_data_volume_type" {
  description = "EBS volume type for data"
  type        = string
  default     = "gp3"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.0"
}

variable "enable_timescaledb" {
  description = "Enable TimescaleDB extension"
  type        = bool
  default     = true
}

variable "database_enable_backups" {
  description = "Enable automated backups to S3"
  type        = bool
  default     = true
}

variable "database_backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "database_backup_s3_bucket" {
  description = "S3 bucket for database backups"
  type        = string
  default     = ""
}

# =============================================================================
# Kong API Gateway Configuration
# =============================================================================

variable "kong_instance_type" {
  description = "Instance type for Kong API Gateway"
  type        = string
  default     = "t3.medium"
}

variable "kong_instance_count" {
  description = "Number of Kong instances (for HA)"
  type        = number
  default     = 1
  validation {
    condition     = var.kong_instance_count >= 1 && var.kong_instance_count <= 3
    error_message = "Kong instance count must be between 1 and 3."
  }
}

variable "kong_version" {
  description = "Kong version"
  type        = string
  default     = "3.5"
}

variable "kong_database_name" {
  description = "Database name for Kong"
  type        = string
  default     = "kong"
}

variable "kong_admin_api_uri" {
  description = "Kong Admin API URI"
  type        = string
  default     = "http://localhost:8001"
}

# =============================================================================
# Microservices Auto Scaling Configuration
# =============================================================================

variable "microservices_instance_type" {
  description = "Instance type for microservices"
  type        = string
  default     = "t3.medium"
}

variable "microservices_in_private_subnet" {
  description = "Place microservices in private subnet"
  type        = bool
  default     = false  # In public for AWS Academy simplicity
}

variable "microservices_min_size" {
  description = "Minimum number of microservice instances"
  type        = number
  default     = 1
}

variable "microservices_max_size" {
  description = "Maximum number of microservice instances"
  type        = number
  default     = 4
}

variable "microservices_desired_capacity" {
  description = "Desired number of microservice instances"
  type        = number
  default     = 2
}

variable "microservices_enable_scaling" {
  description = "Enable auto-scaling policies"
  type        = bool
  default     = true
}

variable "microservices_scale_up_cpu" {
  description = "CPU threshold for scaling up (%)"
  type        = number
  default     = 70
}

variable "microservices_scale_down_cpu" {
  description = "CPU threshold for scaling down (%)"
  type        = number
  default     = 30
}

variable "microservices_services" {
  description = "List of microservices to deploy"
  type = list(object({
    name  = string
    image = string
    port  = number
  }))
  default = [
    {
      name  = "auth-service"
      image = "auth-service:latest"
      port  = 3001
    }
  ]
}

# =============================================================================
# Docker Registry Configuration
# =============================================================================

variable "docker_registry" {
  description = "Docker registry URL (ECR or Docker Hub)"
  type        = string
  default     = ""
}

variable "docker_registry_username" {
  description = "Docker registry username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "docker_registry_password" {
  description = "Docker registry password"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "create_sns_topic" {
  description = "Create SNS topic for monitoring alerts"
  type        = bool
  default     = true
}

variable "monitoring_email_endpoints" {
  description = "Email addresses to receive monitoring alerts"
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}
