# ------------------------------------------------------------------------------
# App IRSA (section 6): api-sa, worker-sa, admin-sa, fastapi-sa
# Namespace: consultation-prod (design 3.3)
# ------------------------------------------------------------------------------
locals {
  app_namespace = "consultation-prod"
  app_service_accounts = [
    { name = "api-sa", role_name_suffix = "api" },
    { name = "worker-sa", role_name_suffix = "worker" },
    { name = "admin-sa", role_name_suffix = "admin" },
    { name = "fastapi-sa", role_name_suffix = "fastapi" },
  ]
}

resource "aws_iam_role" "app" {
  for_each = { for sa in local.app_service_accounts : sa.name => sa }

  name = "${var.cluster_name}-${each.value.role_name_suffix}-irsa"

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
            "${local.oidc_issuer_short}:sub" = "system:serviceaccount:${local.app_namespace}:${each.value.name}"
          }
        }
      }
    ]
  })
}

# SSM Parameter Store read-only for /config/consultation-service/*
data "aws_iam_policy_document" "app_ssm" {
  statement {
    sid    = "SSMGetParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      # "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/config/consultation-service/*"
      "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/config/*"
    ]
  }
}

resource "aws_iam_policy" "app_ssm" {
  name        = "${var.cluster_name}-app-ssm-read"
  description = "SSM Parameter Store read for consultation-service config path"
  policy      = data.aws_iam_policy_document.app_ssm.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  for_each = { for sa in local.app_service_accounts : sa.name => sa }

  role       = aws_iam_role.app[each.value.name].name
  policy_arn = aws_iam_policy.app_ssm.arn
}

# CloudWatch Logs (for all app SAs)
data "aws_iam_policy_document" "app_logs" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_logs" {
  name        = "${var.cluster_name}-app-logs"
  description = "CloudWatch Logs write for app pods"
  policy      = data.aws_iam_policy_document.app_logs.json
}

resource "aws_iam_role_policy_attachment" "app_logs" {
  for_each = { for sa in local.app_service_accounts : sa.name => sa }

  role       = aws_iam_role.app[each.value.name].name
  policy_arn = aws_iam_policy.app_logs.arn
}
