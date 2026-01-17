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
# Multi-Account AWS Configuration
# =============================================================================

variable "account_type" {
  description = "Type of AWS account: 'hub' (central account with shared resources) or 'service' (secondary account for microservices only)"
  type        = string
  default     = "hub"
  validation {
    condition     = contains(["hub", "service"], var.account_type)
    error_message = "account_type must be either 'hub' or 'service'."
  }
}

variable "account_id" {
  description = "AWS Account ID (optional, will be auto-detected if not provided)"
  type        = string
  default     = ""
}

variable "hub_account_id" {
  description = "AWS Account ID of the hub account (required for service accounts)"
  type        = string
  default     = ""
  validation {
    condition     = var.account_type != "service" || var.hub_account_id != ""
    error_message = "hub_account_id is required when account_type is 'service'."
  }
}

variable "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID for cross-account communication (optional)"
  type        = string
  default     = ""
}

variable "cross_account_security_group_ids" {
  description = "List of security group IDs from other accounts for cross-account communication"
  type        = list(string)
  default     = []
}

variable "hub_vpc_cidr" {
  description = "CIDR block of the hub VPC (for security group rules)"
  type        = string
  default     = ""
}

variable "service_account_vpc_cidrs" {
  description = "List of CIDR blocks from service account VPCs (for hub account security groups)"
  type        = list(string)
  default     = []
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
  default     = "academic-platform-key"
}

variable "create_key_pair" {
  description = "Whether to create a new key pair in AWS (set to false to use existing key pair)"
  type        = bool
  default     = true
}

variable "save_key_pair_locally" {
  description = "Whether to save the private key to a local file (only if create_key_pair is true)"
  type        = bool
  default     = true
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

variable "bastion_root_volume_size" {
  description = "Size of root volume for Bastion Host in GB (minimum 30GB for Amazon Linux 2023)"
  type        = number
  default     = 30
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
  description = "Size of root volume in GB (minimum 30GB for Amazon Linux 2023)"
  type        = number
  default     = 30
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

variable "enable_mongodb" {
  description = "Enable MongoDB (NoSQL database)"
  type        = bool
  default     = true
}

variable "mongodb_version" {
  description = "MongoDB version"
  type        = string
  default     = "7.0"
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

variable "kong_enable_asg" {
  description = "Enable Auto Scaling Group for Kong (if false, uses EC2 instances directly)"
  type        = bool
  default     = false
}

variable "kong_min_size" {
  description = "Minimum number of Kong instances in ASG"
  type        = number
  default     = 1
}

variable "kong_max_size" {
  description = "Maximum number of Kong instances in ASG"
  type        = number
  default     = 2
}

variable "kong_desired_capacity" {
  description = "Desired number of Kong instances in ASG"
  type        = number
  default     = 1
}

variable "kong_health_check_grace_period" {
  description = "Grace period for Kong health checks (seconds)"
  type        = number
  default     = 300
}

variable "kong_load_balancer_internal" {
  description = "Whether the Kong load balancer is internal (private) or internet-facing"
  type        = bool
  default     = false
}

variable "kong_allocate_eip_per_instance" {
  description = "Allocate Elastic IP per Kong instance (only when ASG is disabled)"
  type        = bool
  default     = false
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

variable "microservices_enable_load_balancer" {
  description = "Enable Application Load Balancer for microservices"
  type        = bool
  default     = true
}

variable "microservices_load_balancer_internal" {
  description = "Whether the load balancer is internal (private) or internet-facing"
  type        = bool
  default     = false
}

variable "microservices_enable_elastic_ips" {
  description = "Enable Elastic IPs for microservices (one per service)"
  type        = bool
  default     = false
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

# =============================================================================
# Service Account Overrides (for cross-account communication)
# =============================================================================

variable "database_host_override" {
  description = "Database host IP (for service accounts connecting to hub account database)"
  type        = string
  default     = ""
}

variable "redis_host_override" {
  description = "Redis host IP (for service accounts connecting to hub account redis)"
  type        = string
  default     = ""
}

variable "kong_endpoint_override" {
  description = "Kong endpoint URL (for service accounts connecting to hub account Kong)"
  type        = string
  default     = ""
}
