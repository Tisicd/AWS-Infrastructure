variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster (should include both public and private)"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = null
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the public endpoint (empty list means all IPs)"
  type        = list(string)
  default     = []
}

variable "enabled_cluster_log_types" {
  description = "List of enabled EKS cluster log types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "node_role_arn" {
  description = "ARN of existing IAM role for EKS nodes (if provided, creates managed node group)"
  type        = string
  default     = ""
}

variable "instance_types" {
  description = "List of EC2 instance types for nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Disk size in GB for nodes"
  type        = number
  default     = 20
}

variable "capacity_type" {
  description = "Type of capacity for managed node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "ami_type" {
  description = "AMI type for managed node group (AL2023_x86_64_STANDARD for Kubernetes 1.33+, AL2_x86_64 for 1.32 or earlier)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}




