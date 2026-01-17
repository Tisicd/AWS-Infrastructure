variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access public services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "your_ip_cidr" {
  description = "Your IP address in CIDR format"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_bastion" {
  description = "Enable Bastion security group"
  type        = bool
  default     = true
}

variable "enable_kong" {
  description = "Enable Kong security group"
  type        = bool
  default     = true
}

variable "enable_microservices" {
  description = "Enable Microservices security group"
  type        = bool
  default     = true
}

variable "enable_database" {
  description = "Enable Database security group"
  type        = bool
  default     = true
}

variable "enable_load_balancer" {
  description = "Enable Load Balancer security group"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Multi-Account Configuration
# =============================================================================

variable "account_type" {
  description = "Type of AWS account: 'hub' or 'service'"
  type        = string
  default     = "hub"
}

variable "hub_account_id" {
  description = "AWS Account ID of the hub account"
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