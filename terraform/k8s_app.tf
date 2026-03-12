# ------------------------------------------------------------------------------
# App namespace and workloads (sections 3.3, 4, 4.3, 5)
# Terraform: Namespace, ServiceAccount(IRSA), Service, Ingress, HPA only.
# Deployments are in k8s-manifests/ and applied via kubectl (see docs/CI_CD_EKS.md).
# ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "consultation_prod" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name = local.app_namespace # from iam_app.tf
  }

  depends_on = [
    helm_release.karpenter,
    helm_release.aws_load_balancer_controller,
  ]
}

# ServiceAccounts with IRSA annotation (created before Deployments)
resource "kubernetes_service_account_v1" "app" {
  for_each = var.install_app_manifests ? { for sa in local.app_service_accounts : sa.name => sa } : {}

  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app[each.value.name].arn
    }
  }
}

# API module: Service only (Deployment is in k8s-manifests/, applied via kubectl)
resource "kubernetes_service_v1" "api" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "api"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/actuator/health"
    }
  }
  spec {
    selector = { app = "api" }
    port {
      port        = 8081
      target_port = 8081
    }
    type = "ClusterIP"
  }
}

# Admin module: Service only (Deployment in k8s-manifests/)
resource "kubernetes_service_v1" "admin" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "admin"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/actuator/health"
    }
  }
  spec {
    selector = { app = "admin" }
    port {
      port        = 8082
      target_port = 8082
    }
    type = "ClusterIP"
  }
}

# FastAPI module: Service only (Deployment in k8s-manifests/)
resource "kubernetes_service_v1" "fastapi" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "fastapi"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/fastapi/health"
    }
  }
  spec {
    selector = { app = "fastapi" }
    port {
      port        = 8000
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

# Worker module: Service only (Deployment in k8s-manifests/)
resource "kubernetes_service_v1" "worker" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "worker"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
  }
  spec {
    selector = { app = "worker" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# Ingress: single ALB, path-based (section 5)
resource "kubernetes_ingress_v1" "main" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "consultation-ingress"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                       = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"             = "ip"
      "alb.ingress.kubernetes.io/security-groups"         = local.alb_sg_id
      "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "false"
    }
  }
  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/admin"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.admin[0].metadata[0].name
              port {
                number = 8082
              }
            }
          }
        }
        path {
          path      = "/fastapi"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.fastapi[0].metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.api[0].metadata[0].name
              port {
                number = 8081
              }
            }
          }
        }
      }
    }
  }
}

# HPA (section 4.1)
resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "api"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
  }
  spec {
    min_replicas = var.api_min_replicas
    max_replicas = var.api_max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "api"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "admin" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "admin"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
  }
  spec {
    min_replicas = var.admin_min_replicas
    max_replicas = var.admin_max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "admin"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "fastapi" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "fastapi"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
  }
  spec {
    min_replicas = var.fastapi_min_replicas
    max_replicas = var.fastapi_max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "fastapi"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "worker" {
  count = var.install_app_manifests ? 1 : 0

  metadata {
    name      = "worker"
    namespace = kubernetes_namespace_v1.consultation_prod[0].metadata[0].name
  }
  spec {
    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "worker"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}
