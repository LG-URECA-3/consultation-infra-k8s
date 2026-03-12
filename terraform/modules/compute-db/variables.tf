variable "project_name" {
  description = "Project name for resource naming and tags"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for DB instances (Amazon Linux 2023 or compatible)"
  type        = string
  default     = null
}

variable "mysql_primary_ami_id" {
  description = "AMI ID for MySQL primary instance"
  type        = string
  default     = null
}

variable "mysql_replica_ami_id" {
  description = "AMI ID for MySQL replica instance"
  type        = string
  default     = null
}

variable "db_instance_type" {
  description = "EC2 instance type for MySQL (Master/Slave)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used for DB instances"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for DB/backend instances"
  type        = string
}

variable "app_instance_profile_name" {
  description = "IAM instance profile name for DB instances"
  type        = string
}

variable "mysql_primary_target_group_arn" {
  description = "Target group ARN for MySQL Primary (NLB 3306 when not in failover)"
  type        = string
}

variable "mysql_replica_target_group_arn" {
  description = "Target group ARN for MySQL Replica (NLB 3306 when in failover)"
  type        = string
}

variable "enable_mysql_replica" {
  description = "If true, create MySQL replica instance and attach to replica target group. If false, only primary is created."
  type        = bool
  default     = false
}

variable "key_name" {
  description = "EC2 key pair name for SSH access to MySQL instances"
  type        = string
  default     = null
}

