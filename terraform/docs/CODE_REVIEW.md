# consultation-infra-k8s 코드 검토 결과

전체 Terraform 코드를 검토한 결과입니다. **아래 1번 섹션은 이미 반영된 상태**이며, 2번 이후는 확인·참고 사항입니다.

---

## 1. 반영 완료 (이전 검토 권장 사항)

### 1.1 ALB 구성

- **현재**: `modules/lb`는 **NLB만** 생성(MySQL/Redis/Kafka/ES). `app_alb` 없음.
- 트래픽은 Ingress + AWS Load Balancer Controller가 생성하는 ALB로 처리.

### 1.2 Ingress ALB 보안 그룹

- **현재**: `k8s_app.tf` Ingress에 `alb.ingress.kubernetes.io/security-groups = local.alb_sg_id` annotation 적용됨.
- Ingress ALB가 `alb_sg`를 사용해 `eks_node_sg` 규칙과 일치.

### 1.3 Outputs

- **현재**: `alb_dns_name`/`alb_zone_id`는 없음. Ingress ALB는 `ingress_alb_dns_name`(install_app_manifests 시) 등으로 안내.

---

## 2. 확인·사전 설정 필요 (Medium)

### 2.1 Bastion / 데이터 계층 EC2 — key_name

**현재**  
- `create_bastion = true`일 때 `ssh_key_name` **필수**: 변수 validation으로 null/빈 문자열 불가.
- `ssh_key_name` 기본값: `consultation-service-key`.
- 데이터 계층 EC2(MySQL, Redis, Kafka, ES)도 `key_name = var.ssh_key_name` 사용. SSM Session Manager로도 접근 가능.  

---

### 2.2 SSM Parameter Store

**현상**  
- `ssm-parameters.tf` 에서 DB/Redis/Kafka/ES 연결 정보 및 민감 정보를 등록합니다.  
- 민감 정보(`db_root_password`, `db_user`, `db_password`, `redis_password`)는 변수(`ssm_*`)로 주입 시에만 생성됩니다.

**권장**  
- 데이터 계층 EC2를 사용하려면 `terraform.tfvars` 에 `ssm_db_root_password`, `ssm_db_user`, `ssm_db_password`, `ssm_redis_password` 를 설정해야 합니다.  

---

### 2.3 EKS Addon 버전

**현상**  
- `eks_addons.tf`에 vpc-cni, coredns, kube-proxy 버전이 고정됨  
- EKS 클러스터 버전 업그레이드 시 addon 호환성 확인 필요  

**권장**  
- EKS 1.32 기준으로 권장 addon 버전 확인  
- `aws eks describe-addon-versions`로 호환 버전 검증  

---

### 2.4 Worker Deployment — health probe 없음

**현상**  
- `kubernetes_deployment.worker`에 liveness/readiness probe 없음  
- `kubernetes_service.worker`는 8080 포트 노출  

**권장**  
- worker가 health endpoint를 제공하면 probe 추가  
- 제공하지 않으면 현재 상태 유지  

---

## 3. 정상 동작 확인 (OK)

| 항목 | 상태 |
|------|------|
| NAT Gateway | `enable_nat_gateway`로 제어, `modules/network`에서 정상 구성 |
| `locals` (vpc_id, private_subnet_ids 등) | `base_infra.tf`에서 정의, 다른 모듈에서 일관 사용 |
| `db_sg` → eks_node_sg | `security.tf`에서 EKS 노드 → DB 접근 규칙 추가됨 |
| NLB target group | `modules/lb`에서 MySQL/Redis/Kafka/ES listener 정의, `data_layer.tf`에서 attachment |
| Karpenter | NodePool, EC2NodeClass, subnet tag, security group tag 일치 |
| IRSA | api/worker/admin/fastapi-sa에 SSM, CloudWatch Logs 권한 부여 |
| Ingress path | `/admin`, `/fastapi`, `/` 순서 적절 |
| FastAPI health check | `/fastapi/health` 사용 |
| ALB target group health check | api/admin `/actuator/health`, fastapi `/fastapi/health` |
| 데이터 계층 | `compute_db`, `compute_data` 모듈, `db_sg`, NLB target group 정상 연결 |

---

## 4. 기타 참고

### 4.1 modules/security

- 현재 `modules/security`에는 `alb_sg`, `db_sg`, `bastion_sg`만 있음 (app_sg 없음).
- EKS 사용 시 app 트래픽: Ingress ALB(`alb_sg`) → eks_node_sg → Pod.
- `db_sg` 인바운드는 `security.tf`의 `db_from_eks_node_*` 규칙으로 EKS 노드 접근 허용.  

### 4.2 Karpenter amiFamily

- `EC2NodeClass`에 `amiFamily = "AL2"` 사용  
- ARM64(t4g) 지원 확인 필요  

### 4.3 variables.tf 기본값

- `db_instance_type`: t4g.medium  
- `enable_mysql_replica`: false  
- `api_max_replicas` 등: 2  

---

## 5. 요약

| 우선순위 | 항목 | 상태 |
|----------|------|------|
| 반영 완료 | ALB | lb 모듈은 NLB만 생성, Ingress가 ALB 생성 |
| 반영 완료 | Ingress ALB SG | annotation 적용됨 |
| 반영 완료 | Bastion | create_bastion=true 시 ssh_key_name validation + 기본값 |
| 확인 | SSM | 데이터 계층 EC2 사용 시 ssm_* 파라미터 필수 |
| 확인 | EKS addon | 클러스터 버전과 addon 호환성 확인 |
