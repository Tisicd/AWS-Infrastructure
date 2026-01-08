variable "project_name" { type = string }
variable "environment" { type = string }
variable "create_sns_topic" {
  type = bool
  default = true
}
variable "sns_email_endpoints" {
  type = list(string)
  default = []
}
variable "log_retention_days" {
  type = number
  default = 7
}
variable "enable_alarms" {
  type = bool
  default = true
}
variable "kong_instance_ids" {
  type = list(string)
  default = []
}
variable "database_instance_ids" {
  type = list(string)
  default = []
}
variable "microservices_asg_name" {
  type = string
  default = ""
}
variable "tags" {
  type = map(string)
  default = {}
}

