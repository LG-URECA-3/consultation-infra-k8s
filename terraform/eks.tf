# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
    public_access_cidrs    = var.cluster_endpoint_public_access_cidrs
    security_group_ids     = [] # Use cluster default; node SG handles node traffic
  }

  enabled_cluster_log_types = var.enable_cluster_logging ? ["api", "audit", "authenticator", "controllerManager", "scheduler"] : []

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_cluster_policy,
    aws_iam_role_policy_attachment.cluster_eks_vpc_resource_controller,
  ]
}

# ------------------------------------------------------------------------------
# System Managed Node Group (private subnets only, uses custom launch template for eks-node-sg)
# AMI: let EKS choose AL2023 ARM64 AMI via ami_type on node group (no image_id in launch template)
# ------------------------------------------------------------------------------
resource "aws_launch_template" "system_node" {
  name_prefix   = "${var.cluster_name}-system-"
  instance_type = var.system_node_instance_types[0]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  vpc_security_group_ids = [aws_security_group.eks_node.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-system"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Update node group to use launch template
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  ami_type        = "AL2023_ARM_64_STANDARD"
  subnet_ids      = local.private_subnet_ids

  launch_template {
    id      = aws_launch_template.system_node.id
    version = aws_launch_template.system_node.latest_version
  }

  scaling_config {
    desired_size = var.system_node_desired_size
    max_size     = var.system_node_max_size
    min_size     = var.system_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "role" = "system"
  }

  tags = {
    Name = "${var.cluster_name}-system"
    "karpenter.sh/discovery" = var.cluster_name
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_eks_worker_policy,
    aws_iam_role_policy_attachment.node_eks_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
  ]
}
