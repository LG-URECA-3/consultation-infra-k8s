variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "mysql_listener_use_replica" {
  type    = bool
  default = false
}
