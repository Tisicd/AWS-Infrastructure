variable "use_existing_vpc" {
  description = "Whether to use an existing VPC or create a new one"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID to use when use_existing_vpc is true"
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC (only used when use_existing_vpc is false)"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name (for Kubernetes tags)"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "uce"
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs (required when use_existing_vpc is true)"
  type        = list(string)
  default     = []
}

variable "public_subnet_count" {
  description = "Number of public subnets to create (only used when use_existing_vpc is false)"
  type        = number
  default     = 2
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones to use (if empty, uses available AZs)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}




