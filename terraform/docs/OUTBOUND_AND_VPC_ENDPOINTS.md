# 아웃바운드 의존성 분석 및 VPC Endpoint vs NAT 비용 검토

이 문서는 **consultation-service**, **consultation-ai** 및 **consultation-infra-k8s** 기준으로  
프라이빗 서브넷(EKS 노드·파드, 데이터 계층 EC2)에서 발생하는 **아웃바운드 트래픽**을 정리하고,  
**NAT Gateway 대비 VPC Endpoint**로 비용 절감이 가능한지 검토합니다.

---

## 1. 아웃바운드 의존성 요약

### 1.1 consultation-service (Spring Boot)

| 대상 | 용도 | AWS 서비스 여부 | NAT 경유 | 비고 |
|------|------|-----------------|----------|------|
| **SSM Parameter Store** | prod 설정 로드 (db_url, redis_host, jwt_secret 등) | 예 | **예** | NAT 경유 (VPC Endpoint 미사용) |
| **MySQL** | JPA/DB | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **Redis** | 캐시/큐 | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **Kafka** | 이벤트 | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **Elasticsearch** | Admin 헬스체크 | 설정에 따라 (VPC 내면 해당 없음) | 설정 의존 | 내부 NLB 사용 시 NAT 불필요 |
| **Google Gemini API** | Worker 상담 요약 | 아니오 | **예** | 공인 인터넷 필수 |
| **Google OAuth2 / JWKS** | API ID 토큰 검증 | 아니오 | **예** | accounts.google.com |
| **ECR** | 이미지 풀 (EKS 노드) | 예 | **예** | 엔드포인트 없으면 NAT 경유 |

### 1.2 consultation-ai (FastAPI)

| 대상 | 용도 | AWS 서비스 여부 | NAT 경유 | 비고 |
|------|------|-----------------|----------|------|
| **SSM Parameter Store** | prod 설정 (DB, ES, Kafka, Redis, API 키 등) | 예 | **예** | NAT 경유 (VPC Endpoint 미사용) |
| **MySQL** | DB (aiomysql) | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **Elasticsearch** | FAQ/상담 검색 | 설정에 따라 | 설정 의존 | 내부 NLB 사용 시 NAT 불필요 |
| **Kafka** | processing-consultation 구독 | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **Redis** | 캐시/레디니스 | 아니오 (VPC 내 NLB) | 아니오 | 내부 통신 |
| **OpenAI API** | 채팅/임베딩 | 아니오 | **예** | api.openai.com |
| **Friendli AI** | K-EXAONE (OpenAI 호환) | 아니오 | **예** | api.friendli.ai |
| **ECR** | 이미지 풀 (EKS 노드) | 예 | **예** | 엔드포인트 없으면 NAT 경유 |

### 1.3 인프라·런타임 공통 (consultation-infra-k8s)

| 대상 | 용도 | AWS 서비스 여부 | NAT 경유 | 비고 |
|------|------|-----------------|----------|------|
| **SSM** | 데이터 계층 EC2 user_data에서 DB/Redis 비밀번호 등 조회 | 예 | **예** | NAT 경유 (VPC Endpoint 미사용) |
| **ECR** | EKS 노드에서 api/admin/fastapi/worker 이미지 풀 | 예 | **예** | ecr.api + ecr.dkr 미사용 시 |
| **Public ECR** | Karpenter 등 public.ecr.aws 이미지 | 예(퍼블릭) | **예** | 퍼블릭 ECR은 엔드포인트 범위 확인 필요 |
| **CloudWatch** | Container Insights 메트릭 전송 | 예 | **예** | monitoring 엔드포인트 미사용 시 |

---

## 2. NAT를 통해 나가는 트래픽 (요약)

- **AWS 서비스 (현재 NAT 경유, VPC Endpoint로 대체 가능)**  
  - **SSM**: NAT 경유 (현재 VPC Endpoint 미구성)  
  - **ECR** (이미지 풀): NAT 경유, ecr.api + ecr.dkr Interface Endpoint로 대체 가능 → NAT 트래픽 감소  
  - **CloudWatch** (메트릭): NAT 경유, monitoring Interface Endpoint로 대체 가능 → NAT 트래픽 감소  

- **공인 인터넷 (VPC Endpoint 없음, NAT 필수)**  
  - Google (Gemini, OAuth2/JWKS)  
  - OpenAI, Friendli AI  

따라서 **NAT Gateway를 완전히 제거할 수는 없습니다.**  
다만 **NAT 데이터 처리량**을 줄이기 위해 AWS 구간만 VPC Endpoint로 돌리는 것은 가능합니다.

---

## 3. VPC Endpoint 추가 시 비용 추정

### 3.1 가정

- 리전: **ap-northeast-2 (서울)**  
- COST.md 기준: NAT 데이터 **100 GB/월** 중 상당 부분이 ECR 이미지 풀 + 일부 CloudWatch로 가정  
- VPC Interface Endpoint 단가 (서울 리전은 공식 요금표 확인 권장):  
  - **시간당**: 엔드포인트당 AZ당 약 **$0.01/h** (2 AZ 사용 시 엔드포인트당 월 약 **$14.6**)  
  - **데이터 처리**: 약 **$0.01/GB**  

### 3.2 현재 NAT 비용 (COST.md 기준)

- NAT 시간 요금: **$0.062/h × 730 ≒ $45.26/월**  
- NAT 데이터: **$0.062/GB × 100 GB = $6.20/월**  
- **합계: 약 $51.46/월**

### 3.3 시나리오: ECR + CloudWatch VPC Endpoint 추가

| 항목 | 내용 | 월 비용 추정 (USD) |
|------|------|--------------------|
| **ecr.api** | 2 AZ, 시간당 요금 위주, 데이터 소량 | 약 $14.6 |
| **ecr.dkr** | 2 AZ + 이미지 풀 데이터 (예: 50 GB/월) | 약 $14.6 + $0.50 = $15.1 |
| **monitoring** (CloudWatch) | 2 AZ + 메트릭 데이터 (예: 5 GB/월) | 약 $14.6 + $0.05 ≒ $14.65 |
| **NAT 유지** | Google/OpenAI/Friendli 등 공인 인터넷용 (시간 요금 + 잔여 데이터) | $45.26 + (예: 45 GB × $0.062 ≒ $2.79) ≒ $48 |

- **VPC Endpoint 합계**: 약 **$44.35/월**  
- **NAT (유지)**: 약 **$48/월**  
- **총합**: **약 $92/월**  

반면 **현재 구성(NAT만 사용)** 은 **약 $51/월** 이므로,  
**ECR + CloudWatch 엔드포인트를 추가하면 전체 비용이 약 $40/월 정도 증가**합니다.

### 3.4 시나리오: NAT 제거 불가

- Google / OpenAI / Friendli 등 **공인 인터넷 호출이 반드시 필요**하므로 NAT를 제거할 수 없습니다.  
- 따라서 “NAT Gateway **대신** VPC Endpoint만 써서 비용 절감”하는 구성은 불가능합니다.

---

## 4. 결론 및 권장 사항

### 4.1 비용 관점

- **현재 수준(소규모, NAT 100 GB/월 가정)에서는**  
  ECR·CloudWatch용 VPC Endpoint를 **추가하면 NAT 비용은 줄지만**,  
  엔드포인트 시간당 비용이 커서 **전체 비용은 증가**합니다.  
- **NAT 데이터가 매우 큰 경우**(예: 이미지 풀/배포가 많아 월 수백 GB 이상)에는  
  ECR(및 필요 시 CloudWatch) VPC Endpoint 도입 시 **NAT 데이터 요금 절감분이 엔드포인트 비용을 상쇄**할 수 있으므로, 그때 다시 계산하는 것이 좋습니다.

### 4.2 보안·안정성 관점

- **SSM**은 현재 NAT를 통해 접근하며, 필요 시 SSM Interface Endpoint를 추가하면 NAT 트래픽을 줄일 수 있습니다.  
- **ECR**을 VPC Endpoint로 돌리면 이미지 풀 구간이 퍼블릭 인터넷을 타지 않아 보안·정책 관리에 유리할 수 있습니다.  
- **CloudWatch**를 VPC Endpoint로 돌리면 메트릭이 인터넷을 경유하지 않아 네트워크 경로가 단순해집니다.  

즉, **비용만 보면 현재 트래픽 규모에서는 VPC Endpoint 추가는 비용 절감 수단이 아니며**,  
**보안/규정 요구가 있을 때** ECR·CloudWatch 엔드포인트를 검토하는 편이 적절합니다.

### 4.3 요약 표

| 질문 | 답변 |
|------|------|
| NAT Gateway **대신** VPC Endpoint만 써서 비용 절감 가능? | **불가.** Google/OpenAI/Friendli 등 공인 인터넷 통신 때문에 NAT는 필수. |
| VPC Endpoint **추가**로 NAT 비용만 줄이면 전체 비용 절감? | **현재 가정(소규모, 100 GB/월)에서는 불가.** 엔드포인트 시간당 비용 때문에 전체는 증가. |
| 현재 구성의 VPC Endpoint | 없음 (SSM/ECR/CloudWatch 모두 NAT 경유). |
| 추가 검토 가치가 있는 엔드포인트 | **ECR** (ecr.api, ecr.dkr): 이미지 풀 많을 때·보안 요구 시. **CloudWatch** (monitoring): 메트릭 비대할 때·보안 요구 시. |

---

## 5. 참고: VPC Endpoint 추가 시 Terraform

ECR·CloudWatch 엔드포인트를 나중에 도입할 경우,  
**Interface Endpoint**로 추가하면 됩니다.

- **ecr.api**: `com.amazonaws.ap-northeast-2.ecr.api`  
- **ecr.dkr**: `com.amazonaws.ap-northeast-2.ecr.dkr`  
- **monitoring**: `com.amazonaws.ap-northeast-2.monitoring`  

서브넷·보안 그룹은 프라이빗 서브넷(2 AZ) 및 HTTPS(443) 허용 SG를 새로 정의해 사용하면 됩니다.  
정확한 요금은 [AWS PrivateLink 요금](https://aws.amazon.com/privatelink/pricing/) 및 [VPC 요금](https://aws.amazon.com/vpc/pricing/) 문서를 참고하세요.
