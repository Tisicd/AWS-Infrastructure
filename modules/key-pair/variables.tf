variable "key_pair_name" {
  description = "Name of the EC2 Key Pair"
  type        = string
}

variable "create_key_pair" {
  description = "Whether to create a new key pair or use an existing one"
  type        = bool
  default     = true
}

variable "save_private_key" {
  description = "Whether to save the private key to a local file"
  type        = bool
  default     = false
}

variable "private_key_path" {
  description = "Path to save the private key file (if save_private_key is true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to the key pair"
  type        = map(string)
  default     = {}
}
