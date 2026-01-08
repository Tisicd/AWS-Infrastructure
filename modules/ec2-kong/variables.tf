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
variable "allocate_eip_per_instance" {
  type = bool
  default = true
}
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
variable "tags" {
  type = map(string)
  default = {}
}

