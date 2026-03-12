# ------------------------------------------------------------------------------
# General
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for EKS and related resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name for resource naming and tags"
  type        = string
  default     = "consultation"
}

variable "environment" {
  description = "Environment name (e.g. prod, stg)"
  type        = string
  default     = "prod"
}

# ------------------------------------------------------------------------------
# Base infrastructure (created by this module)
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway for private subnet outbound"
  type        = bool
  default     = true
}

variable "mysql_listener_use_replica" {
  description = "If true, NLB 3306 listener forwards to replica target group; otherwise forwards to primary"
  type        = bool
  default     = false
}

variable "create_bastion" {
  description = "Create Bastion host in public subnet"
  type        = bool
  default     = true
}

variable "bastion_ami_id" {
  description = "AMI for Bastion (default: Amazon Linux 2023 ARM)"
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "EC2 key pair name for SSH access (Bastion and data layer EC2). Required when create_bastion=true."
  type        = string
  default     = "consultation-service-key"

  validation {
    condition     = !var.create_bastion || (var.ssh_key_name != null && var.ssh_key_name != "")
    error_message = "When create_bastion is true, ssh_key_name must be set to an existing EC2 key pair name."
  }
}

# ------------------------------------------------------------------------------
# DB / Data layer EC2 (MySQL, Redis, Kafka, Elasticsearch)
# ------------------------------------------------------------------------------
variable "ami_id" {
  description = "Base AMI ID for DB/data instances (Amazon Linux 2023 or compatible); if null, latest AL2023 ARM64 is used"
  type        = string
  default     = null
}

variable "db_instance_type" {
  description = "EC2 instance type for MySQL (Master/Slave)"
  type        = string
  default     = "t4g.medium"
}

variable "es_instance_type" {
  description = "EC2 instance type for Elasticsearch instance"
  type        = string
  default     = "t4g.medium"
}

variable "data_instance_type" {
  description = "EC2 instance type for data layer (ES, Kafka, Redis)"
  type        = string
  default     = "t4g.small"
}

variable "mysql_primary_ami_id" {
  description = "AMI ID for MySQL primary instance (optional override)"
  type        = string
  default     = null
}

variable "mysql_replica_ami_id" {
  description = "AMI ID for MySQL replica instance (optional override)"
  type        = string
  default     = null
}

variable "enable_mysql_replica" {
  description = "Create MySQL replica instance and attach to replica target group"
  type        = bool
  default     = false
}

variable "es_ami_id" {
  description = "AMI ID for Elasticsearch instance (optional override)"
  type        = string
  default     = null
}

variable "kafka_ami_id" {
  description = "AMI ID for Kafka instance (optional override)"
  type        = string
  default     = null
}

variable "redis_ami_id" {
  description = "AMI ID for Redis instance (optional override)"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# SSM Parameter Store (ssm-parameters.tf)
# ------------------------------------------------------------------------------
variable "ssm_alb_dns_name" {
  description = "ALB DNS name for SSM param (Ingress ALB). Set after first apply: kubectl get ingress -n consultation-prod"
  type        = string
  default     = null
}

variable "ssm_db_root_password" {
  description = "MySQL root password (SecureString). Required for data layer EC2."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssm_db_user" {
  description = "MySQL application user (SecureString). Required for data layer EC2."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssm_db_password" {
  description = "MySQL application password (SecureString). Required for data layer EC2."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssm_redis_password" {
  description = "Redis password (SecureString). Required for data layer EC2."
  type        = string
  default     = null
  sensitive   = true
}

# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "consultation-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS control plane"
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API endpoint for EKS"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API endpoint for EKS"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint (e.g. office/VPN IPs)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production
}

# ------------------------------------------------------------------------------
# System Node Group (Managed)
# ------------------------------------------------------------------------------
variable "system_node_desired_size" {
  description = "Desired number of nodes in the system managed node group"
  type        = number
  default     = 2
}

variable "system_node_min_size" {
  description = "Minimum number of nodes in the system managed node group"
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "Maximum number of nodes in the system managed node group"
  type        = number
  default     = 3
}

variable "system_node_instance_types" {
  description = "Instance types for the system node group (run system components + Karpenter)"
  type        = list(string)
  default     = ["t4g.small"]
}

# ------------------------------------------------------------------------------
# Container Insights / Logging
# ------------------------------------------------------------------------------
variable "enable_cluster_logging" {
  description = "Enable EKS control plane logging to CloudWatch"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable Container Insights for the cluster (metrics and logs)"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Optional: Install controllers via Helm (set false to install manually)
# ------------------------------------------------------------------------------
variable "install_aws_load_balancer_controller" {
  description = "Install AWS Load Balancer Controller via Helm"
  type        = bool
  default     = true
}

variable "install_karpenter" {
  description = "Install Karpenter via Helm and create NodePool/EC2NodeClass"
  type        = bool
  default     = true
}

variable "install_app_manifests" {
  description = "Create consultation-prod namespace and app Deployment/Service/Ingress/HPA (placeholder manifests)"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# App images and replicas (section 4)
# ------------------------------------------------------------------------------
variable "ecr_registry" {
  description = "ECR registry URL (default: account.dkr.ecr.region.amazonaws.com)"
  type        = string
  default     = null
}

variable "api_image_tag" {
  description = "API deployment image tag"
  type        = string
  default     = "latest"
}
variable "admin_image_tag" {
  description = "Admin deployment image tag"
  type        = string
  default     = "latest"
}
variable "fastapi_image_tag" {
  description = "FastAPI deployment image tag"
  type        = string
  default     = "latest"
}
variable "worker_image_tag" {
  description = "Worker deployment image tag"
  type        = string
  default     = "latest"
}

variable "api_replicas" {
  description = "API deployment replica count"
  type        = number
  default     = 1
}
variable "admin_replicas" {
  description = "Admin deployment replica count"
  type        = number
  default     = 1
}
variable "fastapi_replicas" {
  description = "FastAPI deployment replica count"
  type        = number
  default     = 1
}
variable "worker_replicas" {
  description = "Worker deployment replica count"
  type        = number
  default     = 1
}

variable "api_min_replicas" {
  description = "API HPA minimum replicas"
  type        = number
  default     = 1
}
variable "api_max_replicas" {
  description = "API HPA maximum replicas"
  type        = number
  default     = 2
}
variable "admin_min_replicas" {
  description = "Admin HPA minimum replicas"
  type        = number
  default     = 1
}
variable "admin_max_replicas" {
  description = "Admin HPA maximum replicas"
  type        = number
  default     = 2
}
variable "fastapi_min_replicas" {
  description = "FastAPI HPA minimum replicas"
  type        = number
  default     = 1
}
variable "fastapi_max_replicas" {
  description = "FastAPI HPA maximum replicas"
  type        = number
  default     = 2
}
variable "worker_min_replicas" {
  description = "Worker HPA minimum replicas"
  type        = number
  default     = 1
}
variable "worker_max_replicas" {
  description = "Worker HPA maximum replicas"
  type        = number
  default     = 2
}
