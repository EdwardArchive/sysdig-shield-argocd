# 설치 및 설정 가이드

## 사전 요구사항

- Kubernetes 클러스터 v1.24 이상, RBAC 활성화
- ArgoCD v2.8 이상 설치 및 구성
- kubectl로 클러스터 접근 가능
- Sysdig Secure 구독 및 Access Key 보유
- (선택) External Secrets Operator, Sealed Secrets, 또는 Vault

## 단계별 설치

### 1. 저장소 복제

```bash
git clone <YOUR_REPO_URL>
cd sysdig-shield-argocd
```

### 2. 시크릿 설정

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

### 3. 개발 환경 배포

```bash
# ArgoCD 애플리케이션 생성
argocd app create -f argocd-apps/sysdig-shield-dev.yaml

# 동기화 확인
argocd app get sysdig-shield-dev
argocd app wait sysdig-shield-dev --health
```

### 4. 배포 확인

```bash
# 파드 상태 확인
kubectl get pods -n sysdig-shield

# Agent 연결 확인
kubectl logs daemonset/sysdig-agent -n sysdig-shield --tail=50 | grep -i "connected"

# Admission Controller 확인
kubectl run test-pod --image=nginx --dry-run=server
```

### 5. 운영 환경 배포

개발/스테이징 검증 완료 후 진행합니다:

```bash
# 운영 애플리케이션 생성 (수동 동기화)
argocd app create -f argocd-apps/sysdig-shield-production.yaml

# 수동 동기화
argocd app sync sysdig-shield-production
argocd app wait sysdig-shield-production --health
```

## ArgoCD 없이 직접 배포 (테스트용)

```bash
kubectl apply -k kustomize/overlays/dev/
```

## 설정 참조

### 환경 변수

#### Sysdig Agent
- `SYSDIG_AGENT_ACCESS_KEY`: Secret에서 가져오는 Access Key
- `COLLECTOR`: 백엔드 URL (기본값: `collector.sysdigcloud.com`)
- `COLLECTOR_PORT`: 백엔드 포트 (기본값: `6443`)
- `SECURE`: 보안 연결 활성화 (기본값: `true`)

#### 리전별 백엔드

| 리전 | Collector URL | API URL |
|------|---------------|---------|
| US1 (기본값) | `collector.sysdigcloud.com` | `app.us1.sysdig.com` |
| US2 | `collector.us2.sysdig.com` | `app.us2.sysdig.com` |
| EU1 | `collector.eu1.sysdig.com` | `app.eu1.sysdig.com` |
| AU1 | `collector.au1.sysdig.com` | `app.au1.sysdig.com` |
| ME2 | `collector.me2.sysdig.com` | `app.me2.sysdig.com` |

> **출처**: [Sysdig SaaS Regions](https://docs.sysdig.com/en/docs/administration/saas-regions-and-ip-ranges/)

### ConfigMap 설정

#### Agent 로그 레벨
- **Dev**: `debug` — 상세 로깅
- **Staging**: `info` — 표준 로깅
- **Production**: `warning` — 최소 로깅

#### Admission Controller 정책
- `failurePolicy`: `Ignore` (dev/staging), `Fail` (production)
- `bypassNamespaces`: kube-system, kube-public, sysdig-shield

### 환경별 리소스 제한

| 컴포넌트 | Dev | Staging | Production |
|----------|-----|---------|------------|
| Agent (CPU) | 100m~500m | 300m~750m | 500m~1000m |
| Agent (Memory) | 256Mi~512Mi | 384Mi~768Mi | 512Mi~1Gi |
| AC (CPU) | 100m~300m | 150m~400m | 200m~500m |
| AC (Memory) | 128Mi~256Mi | 192Mi~384Mi | 256Mi~512Mi |

상세 설정은 `kustomize/overlays/` 내 환경별 리소스 패치 파일을 참조하세요.

## 다음 단계

- [Helm 차트 통합 가이드](helm-integration.md)
- [테스트 및 검증 절차](testing.md)
- [문제 해결 가이드](troubleshooting.md)
- [보안 강화 체크리스트](security.md)
