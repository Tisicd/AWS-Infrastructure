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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
