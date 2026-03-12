variable "project_name" {
  description = "Project name for resource naming and tags"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for data layer instances (Amazon Linux 2023 or compatible)"
  type        = string
  default     = null
}

variable "es_ami_id" {
  description = "AMI ID for Elasticsearch instance"
  type        = string
  default     = null
}

variable "kafka_ami_id" {
  description = "AMI ID for Kafka instance"
  type        = string
  default     = null
}

variable "redis_ami_id" {
  description = "AMI ID for Redis instance"
  type        = string
  default     = null
}

variable "es_instance_type" {
  description = "EC2 instance type for Elasticsearch instance"
  type        = string
}

variable "data_instance_type" {
  description = "EC2 instance type for data layer (ES, Kafka, Redis)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used for data layer instances"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for backend/data instances"
  type        = string
}

variable "app_instance_profile_name" {
  description = "IAM instance profile name for data instances"
  type        = string
}

variable "redis_target_group_arn" {
  description = "Target group ARN for Redis NLB"
  type        = string
}

variable "kafka_target_group_arn" {
  description = "Target group ARN for Kafka NLB"
  type        = string
}

variable "es_target_group_arn" {
  description = "Target group ARN for Elasticsearch NLB"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name for SSH access to data layer instances"
  type        = string
  default     = null
}

