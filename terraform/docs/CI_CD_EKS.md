# EKS 환경 CI/CD 정리

이 문서는 **consultation-infra-k8s** 기준 EKS 클러스터에 애플리케이션(api, admin, fastapi, worker)을 배포하는 CI/CD 관점을 정리합니다.

---

## 0. 역할 분리 (적용됨)

| 구분 | 담당 | 설명 |
|------|------|------|
| **Terraform** | EKS 환경·인프라만 | VPC, 서브넷, NLB, 보안 그룹, EKS, 노드 그룹, Karpenter, LB Controller, **네임스페이스, ServiceAccount(IRSA), Service, Ingress, HPA** 까지만 생성. **Deployment는 Terraform에 없음.** |
| **kubectl** | 앱 배포·롤아웃 | Deployment 매니페스트는 **`terraform/k8s-manifests/`** 에 있으며, `kubectl apply -f` 로 최초 적용 후 이미지 변경은 `kubectl set image` + `rollout status` 로 진행. |

즉, **Terraform은 EKS 환경을 띄우는 역할만** 하고, **앱 Deployment는 이 레포의 YAML을 로컬/CI에서 수정 후 kubectl로 배포**합니다.

---

## 1. 현재 상태

| 구분 | 내용 |
|------|------|
| **consultation-infra-k8s** | 별도 CI/CD 워크플로우 없음. 수동 `terraform apply` 또는 `kubectl`로 배포 가능. |
| **consultation-infra** (EC2/ASG) | `.github/workflows/cd.yml` 존재. `repository_dispatch`(deploy-module) + Terraform 변수 + **ASG Instance Refresh**로 EC2 롤아웃. EKS와 무관. |

EKS로 전환 시에는 **앱 이미지 빌드 → ECR 푸시 → EKS Deployment 반영** 흐름을 새로 정의해야 합니다.

---

## 2. EKS 배포 구조 요약

- **이미지 저장소**: ECR  
  - `{account}.dkr.ecr.{region}.amazonaws.com/consultation-service/{api|admin|fastapi|worker}:{tag}`
- **배포 대상**: 네임스페이스 `consultation-prod`, Deployment 4개 (api, admin, fastapi, worker)
- **Deployment 정의 위치**: **`terraform/k8s-manifests/deployments.yaml`** (이 레포에서 버전 관리, 로컬에서 수정 후 kubectl apply 또는 CI에서 적용)

즉, **새 버전 배포 = YAML의 이미지 수정 또는 `kubectl set image`** 로 반영합니다.

---

## 3. CI/CD 흐름 (권장)

```
[애플리케이션 레포]          [인프라/배포]
       |                            |
       v                            |
  빌드 (Docker)                     |
       |                            |
       v                            |
  ECR 푸시 (이미지:tag)             |
       |                            |
       +---------> 트리거 ---------->+
                                     |
                    +----------------+----------------+
                    |                                 |
                    v                                 v
         방법 A: Terraform apply            방법 B: kubectl set image
         (image tag 변수 변경)              + rollout status
```

### 3.1 공통 전제 (CI)

1. **빌드**: 애플리케이션 레포에서 Docker 이미지 빌드 (api, admin, fastapi, worker 각각 또는 멀티 스테이지).
2. **ECR 푸시**: AWS 계정/리전의 ECR 리포지터리 `consultation-service/api`, `.../admin`, `.../fastapi`, `.../worker`에 태그로 푸시.
3. **인증**: CI 러너가 ECR에 푸시할 수 있도록 AWS 자격 증명(액세스 키 또는 OIDC) 설정.

### 3.2 배포 방법 — kubectl로 이미지 교체 (현재 방식)

- **장점**: Terraform은 인프라만 담당하고, 배포는 kubectl로만 처리. 배포 속도 빠르고 파이프라인 단순.
- **주의**: Terraform이 Deployment 리소스도 관리 중이면, **다음 `terraform apply` 시** 이미지가 변수(`api_image_tag` 등) 값으로 다시 덮어씌워질 수 있음. 그래서 “Terraform = 환경만, 배포 = kubectl”로 가려면 (1) 배포 시 Terraform을 안 돌리거나, (2) Terraform에서 Deployment/이미지는 빼고 네임스페이스·Service·Ingress만 관리하도록 바꾸는 선택이 필요함.

**흐름:**

1. 이미지 빌드 후 ECR에 푸시.
2. EKS 클러스터 접속 자격 확보 (`aws eks update-kubeconfig` 또는 CI용 역할).
3. 이미지만 교체 후 롤아웃:
   ```bash
   kubectl set image deployment/api api=${ECR_URI}/consultation-service/api:v1.2.3 -n consultation-prod
   kubectl rollout status deployment/api -n consultation-prod
   ```
4. admin, fastapi, worker도 동일하게 `deployment/{이름}` 에 대해 실행.

**Deployment 파일 위치:**  
- 이 레포의 **`terraform/k8s-manifests/`** 에서 버전 관리. 로컬에서 YAML 수정 후 `kubectl apply -f k8s-manifests/deployments.yaml` 또는 CI에서 동일하게 적용.  
- 일상 배포는 위의 `kubectl set image` + `rollout status` 만 사용해도 됨.

---

## 4. 권장 파이프라인 (요약)

| 단계 | 담당 | 설명 |
|------|------|------|
| 1. 빌드 | 앱 레포 CI | Docker 빌드, 태그(예: git SHA 또는 버전) 부여 |
| 2. ECR 푸시 | 앱 레포 CI | `consultation-service/{api,admin,fastapi,worker}:{tag}` 푸시 |
| 3. 배포 | CI 또는 수동 | 앱 레포에서 인프라 레포로 웹훅/`repository_dispatch` 등으로 “이 태그로 배포해라” 전달 |
| 4. Terraform apply | 인프라 레포 CD | `consultation-infra-k8s/terraform` 에서 `-var=api_image_tag=...` 등 적용 |
| 5. 롤아웃 확인 | 인프라 레포 CD | 필요 시 `kubectl rollout status` 또는 Terraform apply 완료로 간주 |

앱 레포와 인프라 레포가 다르면, “배포 트리거”에서 인프라 레포의 워크플로를 호출할 때 **배포할 이미지 태그**를 payload로 넘기면 됩니다.

---

## 5. GitHub Actions 예시 (kubectl 배포)

**consultation-infra-k8s** 레포 또는 CI에서: ECR에 이미지 푸시 후 kubectl로 이미지만 교체.

```yaml
# .github/workflows/deploy-eks.yml (예시)
name: Deploy to EKS
on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag (e.g. v1.2.3)'
        required: true
        default: 'latest'
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
          TAG="${{ github.event.inputs.image_tag || 'latest' }}"
          for dep in api admin fastapi worker; do
            kubectl set image deployment/$dep $dep=$ECR/consultation-service/$dep:$TAG -n consultation-prod
          done
          kubectl rollout status deployment/api deployment/admin deployment/fastapi deployment/worker -n consultation-prod --timeout=5m
```

최초 배포 시에는 `kubectl apply -f terraform/k8s-manifests/deployments.yaml` 로 Deployment를 먼저 생성한 뒤, 위처럼 `kubectl set image` 로 이미지만 갱신하면 됩니다.

---

## 6. EKS 접근 권한 (CI/CD)

- **Terraform apply**  
  - Terraform이 EKS 리소스(네임스페이스, Service, Ingress, HPA 등)를 생성/수정하려면: **EKS API 호출 권한** (클러스터가 있는 계정의 IAM).  
  - Terraform 백엔드(S3/DynamoDB) 사용 시 해당 리소스에 대한 권한 필요.
- **kubectl (Deployment 배포·롤아웃)**  
  - `aws eks update-kubeconfig` 후 사용하려면: **EKS `DescribeCluster`**, 클러스터 인증용 **IAM** 권한.  
  - CI에서는 보통 **OIDC + IAM Role** 또는 **액세스 키**로 위 권한을 부여합니다.

---

## 7. 정리

| 항목 | 내용 |
|------|------|
| **Terraform 역할** | EKS 환경(VPC, EKS, NLB, 네임스페이스, Service, Ingress, HPA, ServiceAccount)만 생성. **Deployment는 Terraform에 없음.** |
| **Deployment 관리** | **`terraform/k8s-manifests/deployments.yaml`** 에서 관리. 이 레포에서 버전 관리되며, 로컬에서 수정 후 `kubectl apply` 또는 CI에서 적용. |
| **이후 배포** | **kubectl** (`kubectl set image`, `kubectl apply -f k8s-manifests/deployments.yaml`, `rollout status`)로 앱만 배포. Terraform을 매번 돌리지 않음. |
| **이미지** | ECR `consultation-service/{api,admin,fastapi,worker}:{tag}`. |

원하시면 특정 브랜치·태그 전략이나 모듈별 배포(api만 먼저 등) 시나리오도 같은 문서에 이어서 정리할 수 있습니다.
