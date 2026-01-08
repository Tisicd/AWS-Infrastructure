variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "nat_gateway_count" {
  type = number
  default = 1
}
variable "single_nat_gateway" {
  type = bool
  default = true
}
variable "tags" {
  type = map(string)
  default = {}
}

