variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-west-1"
}

variable "db_password" {
  description = "Password for addr and url databases"
}

variable "key_name" {
  default = "aws_key"
}

variable "public_key_path" {
  description = "public key path"
  default = "~/.ssh/aws_key.pub" 
}

# Generic AMIs
variable "amis_k8" {
  description = "Amazon instance machine images"
  default = {
    us-west-1 = ""
  }
}

# Installed k8 controller applications
variable "amis_k8_controller" {
  description = "Amazon instance machine images"
  default = {
    us-west-1 = "ami-0e117ca6427b9b9a5"
  }
}

# Installed k8 worker applications
variable "amis_k8_worker" {
  description = "Amazon instance machine images"
  default = {
    us-west-1 = "ami-0e4093fc7a9117c07"
  }
}

