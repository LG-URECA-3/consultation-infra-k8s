# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# ------------------------------------------------------------------------------
# OIDC / IRSA (for kubectl or Helm)
# ------------------------------------------------------------------------------
output "oidc_provider_arn" {
  description = "OIDC provider ARN for the cluster (used by IRSA)"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

# ------------------------------------------------------------------------------
# Karpenter
# ------------------------------------------------------------------------------
output "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller (IRSA); set as Helm value controller.serviceAccount.annotations.eks.amazonaws.com/role-arn"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name for Karpenter-provisioned nodes; use in EC2NodeClass spec.instanceProfile"
  value       = aws_iam_instance_profile.karpenter_node.name
}

# ------------------------------------------------------------------------------
# Security / Networking
# ------------------------------------------------------------------------------
output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes (eks-node-sg); used by Karpenter EC2NodeClass securityGroupSelector"
  value       = aws_security_group.eks_node.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by EKS nodes"
  value       = local.private_subnet_ids
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "ingress_alb_dns_name" {
  description = "Ingress ALB DNS (from Ingress status). May be empty until AWS LB Controller provisions it. Run: kubectl get ingress -n consultation-prod"
  value       = var.install_app_manifests ? try(kubernetes_ingress_v1.main[0].status[0].load_balancer[0].ingress[0].hostname, null) : null
}

output "nlb_dns_name" {
  description = "Internal NLB DNS for DB/Redis/Kafka/ES"
  value       = module.lb.nlb_dns_name
}

output "bastion_public_ip" {
  description = "Bastion host public IP (when create_bastion=true)"
  value       = var.create_bastion ? try(aws_instance.bastion[0].public_ip, null) : null
}

# ------------------------------------------------------------------------------
# Data layer (MySQL, Redis, Kafka, Elasticsearch) private IPs
# ------------------------------------------------------------------------------
output "mysql_master_private_ip" {
  description = "Private IP of MySQL master instance"
  value       = module.compute_db.mysql_master_private_ip
}

output "mysql_slave_private_ip" {
  description = "Private IP of MySQL replica instance (null when replica disabled)"
  value       = module.compute_db.mysql_slave_private_ip
}

output "redis_private_ip" {
  description = "Private IP of Redis instance"
  value       = module.compute_data.redis_private_ip
}

output "kafka_private_ip" {
  description = "Private IP of Kafka instance"
  value       = module.compute_data.kafka_private_ip
}

output "elasticsearch_private_ip" {
  description = "Private IP of Elasticsearch instance"
  value       = module.compute_data.elasticsearch_private_ip
}

# ------------------------------------------------------------------------------
# App IRSA role ARNs (section 6; for Helm/manifests or verification)
# ------------------------------------------------------------------------------
output "app_irsa_role_arns" {
  description = "IAM role ARNs for consultation-prod service accounts (api-sa, worker-sa, admin-sa, fastapi-sa)"
  value = {
    api_sa     = aws_iam_role.app["api-sa"].arn
    worker_sa  = aws_iam_role.app["worker-sa"].arn
    admin_sa   = aws_iam_role.app["admin-sa"].arn
    fastapi_sa = aws_iam_role.app["fastapi-sa"].arn
  }
}
