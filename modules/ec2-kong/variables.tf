variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "instance_type" {
  type = string
  default = "t3.medium"
}
variable "instance_count" {
  type = number
  default = 1
}
variable "ami_id" { type = string }
variable "key_name" { type = string }

# Kong Configuration
variable "kong_version" {
  type = string
  default = "3.5"
}
variable "kong_database_host" { type = string }
variable "kong_database_port" {
  type = number
  default = 5432
}
variable "kong_database_name" {
  type = string
  default = "kong"
}
variable "kong_admin_api_uri" {
  type = string
  default = "http://localhost:8001"
}
variable "enable_health_check" {
  type = bool
  default = true
}
variable "health_check_path" {
  type = string
  default = "/status"
}

# Auto Scaling Group Configuration
variable "enable_asg" {
  description = "Enable Auto Scaling Group for Kong (if false, uses EC2 instances directly)"
  type        = bool
  default     = false
}

variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "Grace period for health checks (seconds)"
  type        = number
  default     = 300
}

# Load Balancer Configuration
variable "load_balancer_internal" {
  description = "Whether the load balancer is internal (private) or internet-facing"
  type        = bool
  default     = false
}

variable "load_balancer_subnet_ids" {
  description = "Subnet IDs for the load balancer (should be public subnets for internet-facing)"
  type        = list(string)
}

variable "load_balancer_security_group_ids" {
  description = "Security group IDs for the load balancer"
  type        = list(string)
}

variable "load_balancer_listener_port" {
  description = "Port for the load balancer listener"
  type        = number
  default     = 80
}

variable "load_balancer_listener_protocol" {
  description = "Protocol for the load balancer listener"
  type        = string
  default     = "HTTP"
}

variable "target_group_port" {
  description = "Port for the target group (Kong proxy port)"
  type        = number
  default     = 8000
}

variable "target_group_protocol" {
  description = "Protocol for the target group"
  type        = string
  default     = "HTTP"
}

variable "health_check_matcher" {
  description = "HTTP status codes to use when checking for a successful response"
  type        = string
  default     = "200"
}

# EIP Configuration (only used when ASG is disabled)
variable "allocate_eip_per_instance" {
  description = "Allocate Elastic IP per instance (only when ASG is disabled)"
  type        = bool
  default     = false
}

variable "tags" {
  type = map(string)
  default = {}
}
