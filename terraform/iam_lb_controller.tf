# ------------------------------------------------------------------------------
# AWS Load Balancer Controller IRSA (section 5)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lb_controller" {
  name = "${var.cluster_name}-lb-controller"

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
            "${local.oidc_issuer_short}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.oidc_issuer_short}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# Policy from AWS: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
resource "aws_iam_role_policy" "lb_controller" {
  name = "lb-controller"
  role = aws_iam_role.lb_controller.id

  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}
