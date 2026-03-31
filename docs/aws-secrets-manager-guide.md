# AWS Secrets Manager + External Secrets Operator 가이드

## 개요

여러 클러스터에 Sysdig Shield를 배포할 때, 시크릿(Access Key, API Token)을 각 클러스터에 수동으로 생성하는 대신 **AWS Secrets Manager(SM)에 중앙 관리**하고 **External Secrets Operator(ESO)**가 자동으로 Kubernetes Secret을 생성하도록 구성합니다.

```
┌──────────────────────────┐
│  AWS Secrets Manager     │
│  sysdig/access-key       │
│  sysdig/api-token        │
└────────────┬─────────────┘
             │ 자동 동기화 (주기적)
             ▼
┌──────────────────────────────────────────────┐
│  Kubernetes 클러스터 A     클러스터 B     ...  │
│  ┌──────────────┐    ┌──────────────┐        │
│  │ ESO          │    │ ESO          │        │
│  │  ↓           │    │  ↓           │        │
│  │ K8s Secret   │    │ K8s Secret   │        │
│  │  ↓           │    │  ↓           │        │
│  │ Sysdig Agent │    │ Sysdig Agent │        │
│  └──────────────┘    └──────────────┘        │
└──────────────────────────────────────────────┘
```

**Git에 커밋하는 것**: SecretStore, ExternalSecret (참조만, 평문 없음)
**Git에 커밋하지 않는 것**: 실제 키 값

## 사전 요구사항

- AWS 계정 및 IAM 권한 (Secrets Manager 읽기)
- 각 클러스터에 External Secrets Operator 설치
- ArgoCD (이 저장소의 방식)

## Step 1: AWS Secrets Manager에 시크릿 저장

```bash
# Sysdig Access Key 저장
aws secretsmanager create-secret \
  --name sysdig/access-key \
  --secret-string '{"access-key":"69c9e8da-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}' \
  --region ap-northeast-2

# Sysdig API Token 저장
aws secretsmanager create-secret \
  --name sysdig/api-token \
  --secret-string '{"secure-api-token":"a6efd4ee-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}' \
  --region ap-northeast-2
```

## Step 2: IAM 정책 생성

ESO가 Secrets Manager를 읽을 수 있도록 IAM 정책을 생성합니다:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:sysdig/*"
      ]
    }
  ]
}
```

### 인증 방식 선택

| 방식 | 적합 환경 | 설명 |
|------|----------|------|
| **IRSA** | EKS | ServiceAccount에 IAM Role 연결 (권장) |
| **Access Key** | EKS 외 | IAM User의 Access Key를 K8s Secret으로 |
| **Pod Identity** | EKS 1.24+ | EKS Pod Identity 사용 |

## Step 3: External Secrets Operator 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

> **ArgoCD로 ESO를 설치**하려면 별도의 ArgoCD Application을 생성하면 됩니다.

## Step 4: SecretStore 생성 (Git에 커밋)

### 방식 A: IRSA (EKS 권장)

```yaml
# secrets/external-secrets/secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: sysdig-shield
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

### 방식 B: Access Key (EKS 외)

```yaml
# secrets/external-secrets/secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: sysdig-shield
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
```

```bash
# 이 Secret만 각 클러스터에 수동 생성 (1회)
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id=AKIAXXXXXXXXX \
  --from-literal=secret-access-key=wXXXXXXXXXX \
  -n sysdig-shield
```

### 방식 C: ClusterSecretStore (전체 네임스페이스 공유)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

## Step 5: ExternalSecret 생성 (Git에 커밋)

```yaml
# secrets/external-secrets/external-secret-sysdig-agent.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: sysdig-agent
  namespace: sysdig-shield
spec:
  refreshInterval: 1h          # 1시간마다 AWS SM과 동기화
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: sysdig-agent          # 생성될 K8s Secret 이름
    creationPolicy: Owner
  data:
  - secretKey: access-key       # K8s Secret의 키
    remoteRef:
      key: sysdig/access-key    # AWS SM의 시크릿 이름
      property: access-key      # JSON 내 키

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: sysdig-api-token
  namespace: sysdig-shield
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: sysdig-api-token
    creationPolicy: Owner
  data:
  - secretKey: secure-api-token
    remoteRef:
      key: sysdig/api-token
      property: secure-api-token
```

## Step 6: Helm values에서 Secret 참조

```yaml
# helm-values/base-values.yaml
sysdig_endpoint:
  region: custom
  access_key_existing_secret: sysdig-agent           # ESO가 생성한 Secret
  secure_api_token_existing_secret: sysdig-api-token  # ESO가 생성한 Secret
  api_url: https://sysdig-kakao.cshift.co/
  collector:
    host: sysdig-kakao.cshift.co
    port: 6443
```

## 전체 배포 흐름

```
1. AWS SM에 시크릿 저장 (1회)
2. Git에 커밋:
   - SecretStore (AWS 연결 설정)
   - ExternalSecret (어떤 시크릿을 가져올지)
   - ArgoCD Application (Helm 배포)
   - helm-values/ (existing_secret 참조)
3. 새 클러스터 추가 시:
   - ESO 설치
   - (Access Key 방식이면) aws-credentials Secret 생성
   - ArgoCD Application 적용 → 나머지는 전부 자동
```

## 멀티 클러스터 운영

```
Git 저장소
├── argocd-apps/
│   ├── sysdig-shield-cluster-a.yaml    # Source 2: targetRevision: main
│   ├── sysdig-shield-cluster-b.yaml    # Source 2: targetRevision: main
│   └── sysdig-shield-cluster-c.yaml    # 같은 values, 다른 destination
├── helm-values/
│   ├── base-values.yaml                # 공통 (Secret은 참조만)
│   ├── cluster-a-values.yaml           # 클러스터별 오버라이드
│   └── cluster-b-values.yaml
└── secrets/
    └── external-secrets/
        ├── secret-store.yaml           # 모든 클러스터 공통
        └── external-secret-sysdig-agent.yaml
```

각 클러스터에 필요한 것:
1. ESO 설치 (Helm)
2. (IRSA가 아닌 경우) `aws-credentials` Secret 1개
3. ArgoCD가 나머지 전부 자동 배포

## 검증

```bash
# ExternalSecret 상태 확인
kubectl get externalsecret -n sysdig-shield

# 예상 출력:
# NAME              STORE                  REFRESH   STATUS
# sysdig-agent      aws-secrets-manager    1h        SecretSynced
# sysdig-api-token  aws-secrets-manager    1h        SecretSynced

# 생성된 K8s Secret 확인
kubectl get secret sysdig-agent -n sysdig-shield
kubectl get secret sysdig-api-token -n sysdig-shield
```

## 문제 해결

```bash
# ESO 로그 확인
kubectl logs -n external-secrets-system deployment/external-secrets

# ExternalSecret 상세 상태
kubectl describe externalsecret sysdig-agent -n sysdig-shield

# SecretStore 연결 상태
kubectl describe secretstore aws-secrets-manager -n sysdig-shield
```

## 참고 자료

- [External Secrets Operator 공식 문서](https://external-secrets.io/)
- [ESO + AWS Secrets Manager](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [EKS IRSA 설정](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
