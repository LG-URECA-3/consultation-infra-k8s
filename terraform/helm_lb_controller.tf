# ------------------------------------------------------------------------------
# AWS Load Balancer Controller (section 5) - Helm
# ------------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_aws_load_balancer_controller ? 1 : 0

  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  name             = "aws-load-balancer-controller"
  namespace        = "kube-system"
  version          = "1.7.2"
  create_namespace = false

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lb_controller.arn
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = local.vpc_id
  }

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_addon.vpc_cni,
  ]
}
