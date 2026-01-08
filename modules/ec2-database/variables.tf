variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_type" { 
  type = string
  default = "t3.medium"
}
variable "ami_id" { type = string }
variable "key_name" { type = string }
variable "root_volume_size" {
  type = number
  default = 20
}
variable "data_volume_size" {
  type = number
  default = 50
}
variable "data_volume_type" {
  type = string
  default = "gp3"
}
variable "allocate_eip" {
  type = bool
  default = false
}
variable "postgres_version" {
  type = string
  default = "15"
}
variable "redis_version" {
  type = string
  default = "7.0"
}
variable "enable_timescaledb" {
  type = bool
  default = true
}
variable "enable_automated_backups" {
  type = bool
  default = true
}
variable "backup_retention_days" {
  type = number
  default = 7
}
variable "backup_s3_bucket" {
  type = string
  default = ""
}
variable "tags" {
  type = map(string)
  default = {}
}

