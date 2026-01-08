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

