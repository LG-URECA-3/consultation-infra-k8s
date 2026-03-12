## 개요

이 문서는 `consultation-infra-k8s/terraform` 모듈을 사용해 **VPC ~ EKS ~ 애플리케이션 Pod** 까지 한 번에 배포하는 방법을 정리합니다.

- VPC, Subnet, NAT
- 보안 그룹(`alb_sg`, `db_sg`, `bastion_sg`, `eks-node-sg`)
- SSM Parameter Store (`/config/consultation-service/*`)
- 퍼블릭 ALB + 내부 NLB (MySQL/Redis/Kafka/ES)
- EKS 클러스터 + system node group + Karpenter
- 애플리케이션 네임스페이스(`consultation-prod`) + api/worker/admin/fastapi 배포
- AWS Load Balancer Controller, Karpenter, CloudWatch Container Insights(메트릭 전용)

모든 리소스는 이 레포 안에서 **독립적으로 생성**되며, 다른 Terraform 프로젝트에 의존하지 않습니다.

---

## 선행 조건

- **AWS 계정** 및 적절한 권한 (EKS, EC2, IAM, CloudWatch, ELB, VPC 등)
- **AWS CLI** 설정 완료 (`aws configure` 로 자격 증명/리전을 설정)
- **Terraform** 1.0 이상
- **kubectl**, **Helm** (EKS 클러스터에 애드온/Helm 차트를 배포하는 데 사용)
- 사용 리전: 기본값은 `ap-northeast-2` 이며, 필요 시 `variables.tf` 의 `aws_region` 을 변경할 수 있습니다.

---

## 주요 구성 요소와 파일

- `base_infra.tf`
  - `modules/network`, `modules/security`, `modules/lb` 를 호출하여 VPC, SG, ALB, NLB, Bastion 을 생성합니다.
  - `locals` 로 `local.vpc_id`, `local.private_subnet_ids`, `local.alb_sg_id`, `local.db_sg_id` 등을 다른 파일에서 사용할 수 있게 노출합니다.

- `eks.tf`
  - EKS 클러스터 및 system node group (Managed Node Group)을 생성합니다.
  - 노드는 프라이빗 서브넷에만 배치됩니다.

- `iam.tf`, `iam_app.tf`, `iam_lb_controller.tf`
  - 클러스터/노드 IAM Role, IRSA(Karpenter, AWS Load Balancer Controller, 애플리케이션용 `api-sa`/`worker-sa`/`admin-sa`/`fastapi-sa`) 등을 정의합니다.

- `helm_lb_controller.tf`, `helm_karpenter.tf`, `helm_cloudwatch.tf`
  - AWS Load Balancer Controller, Karpenter, CloudWatch Container Insights(메트릭 전용 DaemonSet)를 Helm으로 설치합니다.

- `security.tf`, `karpenter.tf`
  - `eks-node-sg` 보안 그룹 및 `db_sg` 에 대한 인바운드 규칙(3306/6379/9092/9200 from eks-node-sg).
  - Karpenter용 private subnet 태그(`karpenter.sh/discovery = cluster_name`) 를 추가합니다.

- `k8s_app.tf`
  - `consultation-prod` 네임스페이스 및 api/worker/admin/fastapi Deployment/Service/Ingress/HPA, ServiceAccount(IRSA annotation 포함)를 생성합니다.
  - Ingress(ALB, target-type=ip) 의 path 라우팅(`/`, `/admin`, `/fastapi`) 및 서비스별 헬스체크 경로(`/actuator/health`, `/fastapi/health`) 를 설정합니다.

- `ssm-parameters.tf`
  - DB/Redis/Kafka/ES 연결 정보, 서버 포트 등을 SSM Parameter Store에 등록합니다.
  - 민감 정보(`db_root_password`, `db_user`, `db_password`, `redis_password`)는 변수로 주입 시에만 생성됩니다.

---

## 변수 설정 (`variables.tf`)

필수/자주 사용하는 변수만 요약합니다. 전체 목록은 `variables.tf` 를 참고하세요.

- **일반**
  - `aws_region` (기본: `ap-northeast-2`)
  - `project_name` (기본: `consultation`)
  - `environment` (기본: `prod`)

- **VPC / 서브넷 / NAT**
  - `vpc_cidr` (기본: `10.0.0.0/16`)
  - `availability_zones` (기본: `["ap-northeast-2a", "ap-northeast-2b"]`)
  - `public_subnet_cidrs` (기본: `["10.0.1.0/24", "10.0.2.0/24"]`)
  - `private_subnet_cidrs` (기본: `["10.0.11.0/24", "10.0.12.0/24"]`)
  - `enable_nat_gateway` (기본: `true`)

- **Bastion (선택)**
  - `create_bastion` (기본: `true`)
  - `bastion_ami_id` (기본: `null`, 미지정 시 Amazon Linux 2023 ARM 최신)
  - `ssh_key_name` (Bastion·데이터 계층 EC2 SSH용 키페어. `create_bastion=true`일 때 필수. 기본: `consultation-service-key`)

- **SSM Parameter Store (데이터 계층 EC2 필수)**
  - `ssm_db_root_password`, `ssm_db_user`, `ssm_db_password`, `ssm_redis_password` — null 이면 해당 파라미터 미생성. 데이터 계층 EC2 user_data에서 참조하므로 **반드시 설정**해야 합니다.
  - `ssm_alb_dns_name` (선택) — Ingress ALB DNS. `terraform apply` 후 `kubectl get ingress -n consultation-prod` 로 확인해 설정할 수 있습니다.

- **EKS 클러스터 / 노드 그룹**
  - `cluster_name` (기본: `consultation-eks`)
  - `kubernetes_version` (기본: `1.32`)
  - `cluster_endpoint_public_access` / `cluster_endpoint_private_access`
  - `cluster_endpoint_public_access_cidrs` (API 접근 허용 CIDR, 기본: `["0.0.0.0/0"]` → 운영에서는 반드시 제한 권장)
  - `system_node_desired_size`, `system_node_min_size`, `system_node_max_size`
  - `system_node_instance_types` (기본: `["t4g.small"]`)

- **옵션 컴포넌트**
  - `enable_cluster_logging` (EKS 컨트롤 플레인 로그)
  - `enable_container_insights` (CloudWatch Container Insights 메트릭 DaemonSet + 노드 IAM 권한, 기본: `true`)
  - `install_aws_load_balancer_controller` (기본: `true`)
  - `install_karpenter` (기본: `true`)
  - `install_app_manifests` (기본: `true`)

- **애플리케이션 이미지/스케일링**
  - `ecr_registry` (기본: `null` → `<account>.dkr.ecr.<region>.amazonaws.com` 자동 사용)
  - `api_image_tag`, `admin_image_tag`, `fastapi_image_tag`, `worker_image_tag` (기본: `latest`)
  - `*_replicas`, `*_min_replicas`, `*_max_replicas` (각 모듈별 Deployment/HPA 설정)

---

## 예시 `terraform.tfvars`

운영(prod) 환경에서 기본값 위주로 사용할 수 있는 예시는 다음과 같습니다.

```hcl
project_name = "consultation"
environment  = "prod"

aws_region = "ap-northeast-2"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-northeast-2a", "ap-northeast-2b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

enable_nat_gateway          = true
mysql_listener_use_replica  = false
create_bastion              = false

cluster_name = "consultation-eks"

cluster_endpoint_public_access_cidrs = [
  "203.0.113.0/24", # VPN/office CIDR 등으로 교체
]

enable_cluster_logging    = true
enable_container_insights = true  # 메트릭만 CloudWatch 전송, 로그는 수집 안 함

install_aws_load_balancer_controller = true
install_karpenter                    = true
install_app_manifests                = true

api_image_tag     = "v1.0.0"
admin_image_tag   = "v1.0.0"
worker_image_tag  = "v1.0.0"
fastapi_image_tag = "v1.0.0"
```

---

## 초기화 및 배포

1. **디렉터리 이동**

```bash
cd consultation-infra-k8s/terraform
```

2. **Terraform 초기화**

```bash
terraform init
```

3. **계획 확인**

```bash
terraform plan -out=plan.tfplan
```

리소스 생성/변경 내역을 확인합니다. 처음 실행 시에는 VPC, SG, ALB/NLB, EKS, IAM, Helm 릴리스, Kubernetes 리소스 등 대부분이 신규 생성됩니다.

4. **적용**

```bash
terraform apply plan.tfplan
```

---

## 클러스터 접근 및 애플리케이션 확인

1. **kubeconfig 설정 (AWS CLI 사용)**

```bash
aws eks update-kubeconfig --name <cluster_name> --region <aws_region>
```

예:

```bash
aws eks update-kubeconfig --name consultation-eks --region ap-northeast-2
```

2. **노드 / 파드 상태 확인**

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n consultation-prod
```

3. **Ingress / ALB 확인**

- `kubectl get ingress -n consultation-prod`
- AWS 콘솔의 EC2 → Load Balancers 에서 ALB 의 DNS 이름을 확인하고,  
  `/`, `/admin`, `/fastapi` 경로가 각각 api/admin/fastapi 서비스로 라우팅되는지 테스트합니다.

---

## 비용 관련 주의 사항

- **NAT Gateway**: `enable_nat_gateway = true` 인 경우 시간당 비용이 발생합니다.  
  VPC Endpoint/프라이빗 아웃바운드 전략을 충분히 사용한 뒤 필요 없으면 `false` 로 줄일 수 있습니다.
- **CloudWatch Container Insights**:
  - 이 구성에서는 `aws-cloudwatch-metrics` DaemonSet 을 통해 **메트릭만** CloudWatch 로 전송합니다.
  - 애플리케이션 로그(stdout/stderr) 는 별도로 수집하지 않으므로, 로그 관련 비용은 발생하지 않습니다.
  - 로그 수집이 필요할 때만 `aws-for-fluent-bit` 등 Fluent Bit 차트를 추가하는 것을 권장합니다.

---

## 정리(삭제)

테스트 또는 환경 종료 시 전체 리소스를 제거하려면:

```bash
cd consultation-infra-k8s/terraform
terraform destroy
```

단, 이 명령은 VPC/서브넷/보안그룹/ALB/NLB/EKS/Helm 릴리스/네임스페이스 및 파드를 모두 제거하므로,  
운영 환경에서는 신중히 사용해야 합니다.

