# 앱 Deployment 매니페스트 (kubectl 배포용)

Terraform은 **네임스페이스, Service, Ingress, HPA**만 관리합니다.  
**Deployment**는 이 디렉터리의 YAML로 관리하며, `kubectl apply`로 배포합니다.

## 배치 위치

- **이 레포(consultation-infra-k8s) 안**에서 버전 관리됩니다.
- 로컬에서 수정 후 `kubectl apply` 하거나, CI에서 이미지 태그만 바꿔 적용할 수 있습니다.

## 사전 조건

- Terraform으로 이미 EKS + 네임스페이스 `consultation-prod` + Service/Ingress/ServiceAccount(IRSA)가 생성된 상태여야 합니다.
- `aws eks update-kubeconfig --name <cluster_name> --region <region>` 으로 kubectl이 클러스터를 가리키고 있어야 합니다.

## 이미지 설정

YAML의 `image` 필드에는 **ECR 레지스트리**가 들어갑니다.

- 형식: `<ECR_REGISTRY>/consultation-service/<api|admin|fastapi|worker>:<tag>`
- 예: `123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/consultation-service/api:latest`

**최초 적용 전** 다음 중 하나를 하세요.

1. **YAML에서 직접 수정**  
   `deployments.yaml` 안의 `<ECR_REGISTRY>` 를 실제 값(예: `123456789012.dkr.ecr.ap-northeast-2.amazonaws.com`)으로 바꾼 뒤 apply.
2. **또는** 그대로 apply 한 다음, 이미지만 교체:
   ```bash
   kubectl set image deployment/api api=<ECR_REGISTRY>/consultation-service/api:v1.0.0 -n consultation-prod
   ```

## 적용 방법

```bash
# 네임스페이스 확인 (Terraform이 이미 만들어 둠)
kubectl get ns consultation-prod

# 전체 Deployment 적용
kubectl apply -f deployments.yaml

# 이미지만 바꿔서 롤아웃 (일상적인 배포)
export ECR="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com"
kubectl set image deployment/api     api=${ECR}/consultation-service/api:v1.2.3    -n consultation-prod
kubectl set image deployment/admin  admin=${ECR}/consultation-service/admin:v1.2.3 -n consultation-prod
kubectl set image deployment/fastapi fastapi=${ECR}/consultation-service/fastapi:v1.2.3 -n consultation-prod
kubectl set image deployment/worker worker=${ECR}/consultation-service/worker:v1.2.3 -n consultation-prod
kubectl rollout status deployment/api deployment/admin deployment/fastapi deployment/worker -n consultation-prod
```

## 파일 구성

| 파일 | 내용 |
|------|------|
| `deployments.yaml` | api, admin, fastapi, worker Deployment 정의 (한 파일에 모두 포함). |
| `README.md` | 이 안내. |

Terraform의 Service/Ingress/HPA는 Deployment **이름**(api, admin, fastapi, worker)과 **라벨**(app=api 등)에 맞춰져 있으므로, 이 YAML의 메타데이터/라벨을 바꾸지 마세요.
