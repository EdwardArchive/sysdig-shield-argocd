# 설치 및 설정 가이드

## 사전 요구사항

- Kubernetes 클러스터 v1.24 이상, RBAC 활성화
- ArgoCD v2.8 이상 (Multi-Source Application 지원 필요)
- Sysdig Secure 구독 및 Access Key 보유
- (선택) External Secrets Operator, Sealed Secrets, 또는 Vault

## 단계별 설치

### 1. 저장소 복제

```bash
git clone <YOUR_REPO_URL>
cd sysdig-shield-argocd
```

### 2. ArgoCD Application의 repoURL 설정

`argocd-apps/` 내 각 파일에서 `<YOUR_REPO_URL>`을 실제 Git 저장소 URL로 교체합니다:

```yaml
# argocd-apps/sysdig-shield-dev.yaml 등
sources:
- repoURL: https://charts.sysdig.com    # Helm 차트 (변경 불필요)
  chart: shield
  targetRevision: "1.28.0"
  helm:
    valueFiles:
    - $values/helm-values/base-values.yaml
    - $values/helm-values/dev-values.yaml
- repoURL: <YOUR_REPO_URL>              # ← 여기를 실제 URL로 교체
  targetRevision: HEAD
  ref: values
```

### 3. 시크릿 설정

3가지 방식 중 선택합니다. 자세한 내용은 [`secrets/README.md`](../secrets/README.md)를 참조하세요.

**방식 A: External Secrets Operator (권장)**
```bash
kubectl apply -f secrets/external-secrets/secret-store.yaml
kubectl apply -f secrets/external-secrets/external-secret-sysdig-agent.yaml
```

**방식 B: 수동 Secret 생성 (테스트용)**
```bash
kubectl create namespace sysdig-shield
kubectl create secret generic sysdig-agent \
  --from-literal=access-key=YOUR_SYSDIG_ACCESS_KEY \
  -n sysdig-shield
```

### 4. 개발 환경 배포

```bash
argocd app create -f argocd-apps/sysdig-shield-dev.yaml
argocd app get sysdig-shield-dev
argocd app wait sysdig-shield-dev --health
```

### 5. 배포 확인

```bash
kubectl get pods -n sysdig-shield
kubectl logs daemonset/sysdig-agent -n sysdig-shield --tail=50 | grep -i "connected"
```

### 6. 운영 환경 배포

개발/스테이징 검증 완료 후:

```bash
argocd app create -f argocd-apps/sysdig-shield-production.yaml
argocd app sync sysdig-shield-production
argocd app wait sysdig-shield-production --health
```

## Helm 차트 설정

### 환경별 values 구조

```
helm-values/
├── base-values.yaml          # 모든 환경 공통 (차트: sysdig/shield v1.28.0)
├── dev-values.yaml            # 개발: dryRun=true, 기능 축소
├── staging-values.yaml        # 스테이징: 전체 기능 활성화
└── production-values.yaml     # 운영: failurePolicy=Fail, ML 정책
```

ArgoCD가 `base-values.yaml` + `<env>-values.yaml`을 순서대로 적용합니다. 환경별 파일이 기본값을 오버라이드합니다.

상세 기능별 설정은 [`docs/helm-integration.md`](helm-integration.md)를 참조하세요.

### 리전별 백엔드

`helm-values/base-values.yaml`의 `sysdig_endpoint.region` 값을 변경합니다:

| 리전 | 값 | Collector URL |
|------|-----|---------------|
| US1 (기본값) | `us1` | `collector.sysdigcloud.com` |
| US2 | `us2` | `collector.us2.sysdig.com` |
| EU1 | `eu1` | `collector.eu1.sysdig.com` |
| AU1 | `au1` | `collector.au1.sysdig.com` |
| ME2 | `me2` | `collector.me2.sysdig.com` |

> **출처**: [Sysdig SaaS Regions](https://docs.sysdig.com/en/docs/administration/saas-regions-and-ip-ranges/)

## Helm 없이 직접 배포 (테스트용)

```bash
helm repo add sysdig https://charts.sysdig.com
helm install sysdig-shield sysdig/shield \
  --namespace sysdig-shield --create-namespace \
  --version 1.28.0 \
  -f helm-values/base-values.yaml \
  -f helm-values/dev-values.yaml
```

## 다음 단계

- [Helm 차트 설정 상세](helm-integration.md)
- [테스트 및 검증 절차](testing.md)
- [문제 해결 가이드](troubleshooting.md)
- [보안 강화 체크리스트](security.md)
