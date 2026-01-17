variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "allocate_eip" {
  type    = bool
  default = true
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 30  # Amazon Linux 2023 AMI requires minimum 30GB
}

variable "enable_asg" {
  description = "Enable Auto Scaling Group for automatic instance recovery"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

