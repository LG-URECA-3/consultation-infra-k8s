# ------------------------------------------------------------------------------
# Karpenter (section 3.4) - Helm + NodePool / EC2NodeClass
# ------------------------------------------------------------------------------

# Install Karpenter CRDs (required before controller and manifests)
resource "helm_release" "karpenter_crd" {
  count = var.install_karpenter ? 1 : 0

  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter-crd"
  name             = "karpenter-crd"
  namespace        = "kube-system"
  version          = "1.2.1"
  create_namespace = false

  depends_on = [
    aws_eks_cluster.main
  ]
}

resource "helm_release" "karpenter" {
  count = var.install_karpenter ? 1 : 0

  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  name             = "karpenter"
  namespace        = "kube-system"
  version          = "1.2.1"
  create_namespace = false

  set {
    # name  = "settings.aws.clusterName"
    name = "settings.clusterName"
    value = aws_eks_cluster.main.name
  }
  set {
    # name  = "settings.aws.clusterEndpoint"
    name = "settings.clusterEndpoint"
    value = aws_eks_cluster.main.endpoint
  }
  # set {
  #   name  = "settings.clusterCIDR"
  #   value = "172.20.0.0/16"
  # }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }
  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter_node.name
  }

  depends_on = [
    helm_release.karpenter_crd,
    aws_eks_cluster.main,
    aws_eks_node_group.system,
    aws_eks_addon.vpc_cni,
  ]
}

# NodePool: on-demand only, t4g.small / t4g.medium (design 3.4)
resource "kubernetes_manifest" "karpenter_node_pool" {
  count = var.install_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = "default"
    }

    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }

          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t4g.small", "t4g.medium"]
            }
          ]
        }
      }

      limits = {
        cpu = "20"
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
      }
    }
  }

  depends_on = [
    # helm_release.karpenter_crd,
    # kubernetes_manifest.karpenter_ec2_node_class
  ]
}

# EC2NodeClass: private subnets + eks-node-sg (tags set in security.tf and karpenter.tf)
resource "kubernetes_manifest" "karpenter_ec2_node_class" {
  count = var.install_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily       = "AL2023"
      # # amiFamily = "AL2"
      amiSelectorTerms = [
        {
          id = "ami-055751883cc1be227"
          # alias = "al2023@latest"
          # alias = "al2023@v20241031"
        }
      ]
      instanceProfile = aws_iam_instance_profile.karpenter_node.name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
    }
  }

  depends_on = [
    # helm_release.karpenter_crd,
    # aws_eks_node_group.system
  ]
}
