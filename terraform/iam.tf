# ------------------------------------------------------------------------------
# EKS Cluster IAM Role
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# ------------------------------------------------------------------------------
# EKS Node IAM Role (Managed Node Group + Karpenter-provisioned nodes)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_eks_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# CloudWatch Agent for Container Insights (logging and metrics)
resource "aws_iam_role_policy_attachment" "node_cloudwatch_agent" {
  count = var.enable_container_insights ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.node.name
}

# ------------------------------------------------------------------------------
# Karpenter Controller IRSA
# ------------------------------------------------------------------------------
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer_short = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_short}:sub" = "system:serviceaccount:kube-system:karpenter"
            "${local.oidc_issuer_short}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Karpenter needs to create/delete EC2 instances, launch templates, etc.
resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInstanceProfileReadActions"
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid    = "AllowInstanceProfileTagActions"
        Effect = "Allow"
        Action = [
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid    = "AllowInstanceActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.id}::image/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:key-pair/*"
        ]
      },
      {
        Sid    = "AllowInstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:fleet/*"
        ]
      },
      {
        Sid    = "AllowInstanceReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeVpcs",
          "ec2:DescribeSpotPriceHistory"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowPricingReadActions"
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowInstanceWriteActions"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:launch-template/*"
        ]
      },
      {
        Sid    = "AllowInstanceTerminate"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Sid    = "AllowEKSDescribeCluster"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:aws:eks:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      }
    ]
  })
}

# Karpenter node role = same as EKS node role (used in EC2NodeClass instanceProfile)
# Managed node group uses aws_iam_role.node; Karpenter will use an instance profile
# that references the same node role. We create an instance profile for Karpenter nodes.
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.node.name
}

# ------------------------------------------------------------------------------
# EC2 IAM role for DB / data layer instances (MySQL, Redis, Kafka, Elasticsearch)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "data_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "data_ec2" {
  name               = "${var.project_name}-data-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.data_assume_role.json

  tags = {
    Name = "${var.project_name}-data-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "data_ssm_readonly" {
  role       = aws_iam_role.data_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "data_ecr_readonly" {
  role       = aws_iam_role.data_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "data_ec2" {
  name = "${var.project_name}-data-ec2-instance-profile"
  role = aws_iam_role.data_ec2.name
}

