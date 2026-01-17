variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { 
  type = string
  default = "t3.medium"
}
variable "key_name" { type = string }
variable "min_size" { 
  type = number
  default = 1
}
variable "max_size" {
  type = number
  default = 4
}
variable "desired_capacity" {
  type = number
  default = 2
}
variable "health_check_type" {
  type = string
  default = "EC2"
}
variable "health_check_grace_period" {
  type = number
  default = 300
}
variable "enable_scaling_policies" {
  type = bool
  default = true
}
variable "scale_up_cpu_threshold" {
  type = number
  default = 70
}
variable "scale_down_cpu_threshold" {
  type = number
  default = 30
}
variable "scale_up_adjustment" {
  type = number
  default = 1
}
variable "scale_down_adjustment" {
  type = number
  default = -1
}
variable "services" {
  type = list(object({
    name = string
    image = string
    port = number
  }))
}
variable "database_host" { type = string }
variable "redis_host" { type = string }
variable "kong_endpoint" { type = string }
variable "docker_registry" {
  type = string
  default = ""
}
variable "docker_registry_username" {
  type = string
  default = ""
  sensitive = true
}
variable "docker_registry_password" {
  type = string
  default = ""
  sensitive = true
}
variable "tags" {
  type = map(string)
  default = {}
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Enable Application Load Balancer for microservices"
  type        = bool
  default     = true
}

variable "load_balancer_internal" {
  description = "Whether the load balancer is internal (private) or internet-facing"
  type        = bool
  default     = false
}

variable "load_balancer_subnet_ids" {
  description = "Subnet IDs for the load balancer (should be public subnets for internet-facing)"
  type        = list(string)
  default     = []
}

variable "load_balancer_security_group_ids" {
  description = "Security group IDs for the load balancer"
  type        = list(string)
  default     = []
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
  description = "Port for the target group"
  type        = number
  default     = 3000
}

variable "target_group_protocol" {
  description = "Protocol for the target group"
  type        = string
  default     = "HTTP"
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "HTTP status codes to use when checking for a successful response"
  type        = string
  default     = "200"
}

# Elastic IP Configuration
variable "enable_elastic_ips" {
  description = "Enable Elastic IPs for microservices (one per service). EIPs will be automatically associated with instances via user-data."
  type        = bool
  default     = false
}

# Auto Recovery Configuration
# Note: Auto-recovery is handled automatically by ASG health checks.
# This variable is kept for backward compatibility but has no effect (ASG always handles recovery).
variable "enable_auto_recovery" {
  description = "Auto-recovery is handled automatically by ASG health checks (kept for backward compatibility)"
  type        = bool
  default     = true
}
