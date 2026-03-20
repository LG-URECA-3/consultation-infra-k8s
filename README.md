<div align="center">

# ☁️ LG U+ 프리톡 인프라 (consultation-infra-k8s)
**AWS EKS 기반 클라우드 인프라스트럭처 Terraform 코드 레포지토리**

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Amazon EKS](https://img.shields.io/badge/Amazon_EKS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)

<br/>

> *애플리케이션 계층을 EC2/ASG에서 **EKS Kubernetes Pod**로 전환하고, 전체 환경을 코드로 관리(IaC)하여 **고가용성과 강력한 자동 확장성**을 확보합니다.*

</div>

<br/>

## 📖 프로젝트 개요 (Introduction)

이 레포지토리는 상담 업무 지원 서비스의 클라우드 인프라를 Terraform으로 정의합니다. 기존 EC2/ASG 구조에서 이미지 변경 시 Instance Refresh에 의존하던 방식을 Kubernetes 기반으로 전환하여, **무중단 롤링 배포, 정밀한 헬스체크, HPA 기반의 유연한 자동 확장**을 구현했습니다.

### 🎯 주요 전환 목표

| 계층 | 구성 및 특징 |
| :--- | :--- |
| **애플리케이션 계층** | EC2/ASG 구조에서 **EKS Kubernetes Pod**(`api`, `admin`, `worker`, `fastapi`)로 전면 전환 |
| **데이터 계층** | MySQL, Redis, Kafka, Elasticsearch — 유지보수성을 위해 EC2 + Docker Compose 구조 유지 |
| **스케일링 (Scaling)** | HPA(Pod 수 조절) + Karpenter(노드 수 조절) 이중 자동 확장 파이프라인 구축 |
| **보안 (Security)** | 프라이빗 서브넷 노드 배치, IRSA 최소 권한 부여, SSM Parameter Store 민감 정보 암호화 관리 |
| **모니터링 (Monitoring)**| CloudWatch Container Insights 연동 (비용 최적화를 위해 메트릭 전용 수집) |

---

## 🏗 아키텍처 (Architecture)

```text
                        [ Internet ]
                              |
                    +--------------------+
                    |   Ingress ALB      |  (internet-facing, 80/443)
                    |  path-based route  |
                    |  /        -> api   |
                    |  /admin* -> admin |
                    |  /fastapi*-> fapi  |
                    +--------------------+
                              |
     +================================================================+
     |  VPC  10.0.0.0/16   (ap-northeast-2)                          |
     |                                                                |
     |  [ Public Subnet ]  Bastion EC2, NAT Gateway                  |
     |                                                                |
     |  [ Private Subnet ]                                            |
     |                                                                |
     |  +----------------------EKS Cluster-----------------------+   |
     |  |  kube-system:                                          |   |
     |  |    - AWS Load Balancer Controller                      |   |
     |  |    - Karpenter Controller                              |   |
     |  |    - CloudWatch Metrics DaemonSet                      |   |
     |  |                                                        |   |
     |  |  consultation-prod:                                    |   |
     |  |    Deployment: api (Port 8081)                         |   |
     |  |    Deployment: admin (Port 8082)                       |   |
     |  |    Deployment: fastapi (Port 8000)                     |   |
     |  |    Deployment: worker (Kafka Consumer)                 |   |
     |  +--------------------------------------------------------+   |
     |                                                                |
     |  +-- Internal NLB -----------------------------------------+  |
     |  |  :3306  -> MySQL (Primary / Replica)                     |  |
     |  |  :6379  -> Redis                                         |  |
     |  |  :9092  -> Kafka                                         |  |
     |  |  :9200  -> Elasticsearch                                 |  |
     |  +----------------------------------------------------------+  |
     |                                                                |
     |  Data Layer EC2 (docker compose)                               |
     |    MySQL Primary (t4g.medium), Redis (t4g.small),              |
     |    Kafka (t4g.small), Elasticsearch (t4g.medium)               |
     +================================================================+
```

### 🖥 노드 및 보안 그룹 구성

**노드 구성**
| 노드 그룹 | 역할 | 인스턴스 타입 | 배치 |
| :--- | :--- | :--- | :--- |
| **System Managed** | LB Controller, Karpenter, CoreDNS 등 시스템 컴포넌트 | `t4g.small` | 프라이빗 서브넷 (고정) |
| **Karpenter 프로비저닝** | api, admin, fastapi, worker 애플리케이션 Pod | `t4g.small ~ medium` | 프라이빗 서브넷 (동적 생성) |

**보안 그룹(SG) 관계**
* `alb_sg`: Ingress ALB (80, 443 from 0.0.0.0/0)
* `eks_node_sg`: EKS 워커 노드 (8081, 8082, 8000, 443 from alb_sg / VPC CIDR)
* `db_sg`: 데이터 계층 EC2 (3306, 6379, 9092, 9200 from eks_node_sg; SSH from bastion_sg)
* `bastion_sg`: Bastion 호스트 (22 from 0.0.0.0/0)

---

## 📂 디렉터리 구조 (Directory Structure)

```text
consultation-infra-k8s/
└── terraform/
    ├── base_infra.tf          # VPC, 서브넷, NAT, ALB, NLB, Bastion
    ├── eks.tf                 # EKS 클러스터 + System Managed Node Group
    ├── iam*.tf                # 클러스터/노드 IAM Role, IRSA 설정
    ├── helm*.tf               # AWS LB Controller, Karpenter, CloudWatch Helm 설치
    ├── security.tf            # 보안 그룹 생성 및 규칙 정의
    ├── karpenter.tf           # Karpenter NodePool, EC2NodeClass 정의
    ├── k8s_app.tf             # 네임스페이스, Service, Ingress, HPA 정의
    ├── ssm*.tf                # SSM Parameter Store 및 VPC Endpoints 설정
    ├── data_layer.tf          # 데이터 계층 EC2 (MySQL, Redis, Kafka, ES)
    ├── modules/               # 네트워크, 보안, 로드밸런서, 컴퓨팅 서브 모듈
    ├── k8s-manifests/
    │   └── deployments.yaml   # 애플리케이션 Deployment 매니페스트 (kubectl 배포용)
    └── docs/                  # 상세 아키텍처, 비용, CI/CD 등 추가 문서
```

---

## 🛠 주요 구성 요소 (Key Components)

### 1. Terraform 관리 리소스 (인프라 환경)
VPC, EKS 클러스터, IAM Role, 보안 그룹, 데이터 계층 EC2, SSM 파라미터 등 변하지 않는 인프라의 뼈대를 구성합니다. Kubernetes 내부의 네임스페이스, Service, Ingress, HPA 요소까지 코드로 관리합니다.

### 2. Kubectl 관리 리소스 (애플리케이션 배포)
`k8s-manifests/deployments.yaml` 파일을 통해 앱 이미지와 컨테이너 설정을 관리합니다. 
> 💡 **역할 분리**: Terraform은 인프라 기반을, kubectl(CI/CD)은 실제 애플리케이션 이미지 교체 및 배포를 담당합니다.

### 3. 노드 자동화 (Karpenter)
Pending 상태의 Pod를 감지하여 최적의 EC2 노드를 즉시 프로비저닝합니다. 유휴 노드는 자동 정리되며, 프라이빗 서브넷에 안전하게 배치됩니다.

---

## 🚀 시작하기 (Getting Started)

### 1. 사전 요구사항
* AWS CLI (`aws configure` 자격 증명 완료) 및 권한 (EKS, EC2, IAM, ELB, VPC 등)
* Terraform v1.0 이상
* kubectl, Helm v3.x

### 2. 변수 설정 및 초기화
```bash
$cd consultation-infra-k8s/terraform$ cp terraform.tfvars.example terraform.tfvars
```
`terraform.tfvars` 파일을 열어 `cluster_endpoint_public_access_cidrs` (본인 IP 제한 필수), `ssh_key_name`, 그리고 `ssm_*` 비밀번호 등의 필수 값을 입력합니다.

### 3. 인프라 배포 (Terraform)
```bash
$ terraform init
$terraform plan -out=plan.tfplan$ terraform apply plan.tfplan     # 약 15~20분 소요
```

### 4. 클러스터 연동 및 앱 배포
```bash
# EKS 자격증명 업데이트
$ aws eks update-kubeconfig --name consultation-eks --region ap-northeast-2

# Terraform Output에서 ECR 주소 확인 후 Deployment 배포
$export ECR="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com"$ sed -i "s|<ECR_REGISTRY>|${ECR}|g" k8s-manifests/deployments.yaml
$ kubectl apply -f k8s-manifests/deployments.yaml
```

---

## 🔄 앱 배포 (CI/CD 파이프라인)

배포는 GitHub Actions를 통해 ECR에 이미지를 푸시하고, EKS 클러스터에 `kubectl set image` 명령을 내려 롤링 업데이트를 수행하는 구조입니다.

<details>
<summary><b>🛠 GitHub Actions 워크플로우 예시 보기 (클릭)</b></summary>
<div markdown="1">

```yaml
name: Deploy to EKS
on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag (e.g. v1.2.3)'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2
      - name: Configure kubeconfig
        run: aws eks update-kubeconfig --name consultation-eks --region ap-northeast-2
      - name: Deploy image
        run: |
          ECR="${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.ap-northeast-2.amazonaws.com"
          TAG="${{ github.event.inputs.image_tag }}"
          for dep in api admin fastapi worker; do
            kubectl set image deployment/$dep $dep=$ECR/consultation-service/$dep:$TAG -n consultation-prod
          done
          kubectl rollout status deployment/api deployment/admin deployment/fastapi deployment/worker \
            -n consultation-prod --timeout=5m
```

</div>
</details>

---

## 💻 운영 명령어 (Operations)

```bash
# 클러스터 상태 확인
$ kubectl get nodes
$ kubectl get pods,ingress,hpa -n consultation-prod

# 로그 조회 (예: api, worker)
$kubectl logs -n consultation-prod deployment/api -f$ kubectl logs -n consultation-prod deployment/worker -f

# Bastion 호스트를 통한 Private DB 접근
$terraform output bastion_public_ip$ ssh -i your-key.pem ec2-user@<bastion_public_ip>
$ mysql -h <nlb_dns_name> -P 3306 -u consultation_user -p
```

---

## 💰 비용 참고 (Cost Estimation)

> *서울 리전(`ap-northeast-2`), 온디맨드, 24×7 운영 기준 월 예상 비용입니다.*

| 인프라 영역 | 주요 리소스 구성 | 예상 월 비용 (USD) |
| :--- | :--- | :--- |
| **EKS & 컴퓨팅** | 컨트롤 플레인, System(t4g.small*2), App(t4g.medium*2 평균) | 약 $301 |
| **네트워크** | NAT Gateway(100GB), ALB, NLB | 약 $103 |
| **스토리지/기타** | EBS 볼륨, CloudWatch(Metrics) | 약 $13 |
| **데이터 계층** | MySQL(t4g.m), Redis/Kafka(t4g.s), ES(t4g.m) 및 EBS | 약 $260 |
| **총합계** | | **약 $678 (한화 약 100만 원)** |

💡 **비용 절감 팁:** * **Karpenter**를 통해 야간/비활성 시간대에 노드를 자동 축소하여 App 노드 비용을 크게 절감할 수 있습니다.
* 1~3년 약정(RI / Savings Plans) 적용 시 컴퓨팅 비용의 30~60% 추가 절감이 가능합니다.

---

## 📚 문서 목록 (Documentation)

자세한 아키텍처 및 구축 가이드는 `docs` 폴더 내의 문서를 참고하세요.

* [설계 문서 (README.md)](terraform/README.md)
* [상세 배포 가이드 (SETUP.md)](terraform/SETUP.md)
* [비용 상세 추정 (COST.md)](terraform/docs/COST.md)
* [CI/CD 구축 전략 (CI_CD_EKS.md)](terraform/docs/CI_CD_EKS.md)
