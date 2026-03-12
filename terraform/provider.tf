terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      # v2.x supports helm_release set { } blocks used in this repo
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "consultation-infra-k8s"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. EKS 클러스터 정보 조회용 Data Source
# ------------------------------------------------------------------------------
# 클러스터 이름만 변수 혹은 리소스에서 가져오고,
# 세부 정보(endpoint 등)는 생성 완료 후 data 블록이 동적으로 읽어오게 합니다.
# 주의: 첫 배포 시 apply 시작 시점에는 클러스터가 없어 data가 비어 있으므로,
# Helm/Kubernetes 프로바이더가 "no configuration" 오류를 냅니다.
# → EKS를 먼저 생성한 뒤 전체 apply 하세요. (docs/SETUP.md "첫 배포 시 2단계 적용" 참고)
data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# ------------------------------------------------------------------------------
# 2. Kubernetes / Helm providers (data 블록 참조)
# ------------------------------------------------------------------------------
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # 리소스 직접 참조가 아닌 data 블록 참조를 통해 의존성 분리
    # --region 필수: CI 등에서 AWS_DEFAULT_REGION 미설정 시 "no configuration" 오류 방지
    args = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.main.name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.main.name, "--region", var.aws_region]
    }
  }
}