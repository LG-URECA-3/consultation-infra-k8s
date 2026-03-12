// CloudWatch Container Insights (metrics only via aws-cloudwatch-metrics Helm chart)
// Logs (stdout/stderr) are NOT shipped to CloudWatch to reduce cost.

resource "helm_release" "cloudwatch_metrics" {
  count = var.enable_container_insights ? 1 : 0

  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-cloudwatch-metrics"
  name             = "aws-cloudwatch-metrics"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_addon.vpc_cni,
  ]
}

