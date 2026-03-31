# Sysdig Shield ArgoCD 배포

ArgoCD를 활용한 GitOps 기반 Sysdig Shield 보안 플랫폼의 Kubernetes 클러스터 배포 저장소입니다.

## 개요

이 저장소는 **Sysdig Shield**를 배포하기 위한 ArgoCD Application 매니페스트와 Helm values 설정을 포함합니다. 공식 Sysdig Helm 차트(`sysdig/shield`)를 활용하며, ArgoCD Multi-Source 방식으로 환경별 설정을 관리합니다.

### Sysdig Shield 주요 기능

- **런타임 위협 탐지**: 실시간 보안 모니터링 및 위협 탐지
- **KSPM**: Kubernetes 보안 태세 관리
- **이미지 스캔**: 취약점 평가 및 정책 기반 검증
- **어드미션 컨트롤러**: 배포 시점 정책 제어
- **포렌식**: 상세 조사 및 대응 기능

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      Git 저장소 (이 저장소)                   │
│  ├── argocd-apps/       ArgoCD Application 정의              │
│  ├── helm-values/       환경별 Helm values                   │
│  ├── secrets/           시크릿 관리 템플릿                     │
│  └── test/              테스트 및 검증                        │
└────────────────────┬────────────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
┌──────────────────┐   ┌──────────────────┐
│  charts.sysdig.com│   │  Git 저장소       │
│  (Helm 차트 소스) │   │  (Values 파일)   │
│  sysdig/shield   │   │  helm-values/    │
│  v1.28.0         │   │                  │
└────────┬─────────┘   └────────┬─────────┘
         │  ArgoCD Multi-Source  │
         └──────────┬───────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes 클러스터                               │
│  ┌──────────────────────────────────────────────┐           │
│  │         Sysdig Shield 컴포넌트                 │           │
│  │ • Sysdig Agent (DaemonSet)                   │           │
│  │ • Admission Controller (Deployment + HPA)    │           │
│  │ • Node Analyzer (DaemonSet)                  │           │
│  │ • KSPM Collector (Deployment)                │           │
│  └──────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## 사전 요구사항

- **Kubernetes 클러스터**: v1.24 이상, RBAC 활성화
- **ArgoCD**: v2.8 이상 (Multi-Source 지원 필요)
- **Sysdig 계정**: Sysdig Secure 구독 및 Access Key

## 빠른 시작

### 1. 시크릿 설정

```bash
kubectl create namespace sysdig-shield

kubectl create secret generic sysdig-agent \
  --from-literal=access-key=YOUR_SYSDIG_ACCESS_KEY \
  -n sysdig-shield
```

### 2. ArgoCD Application의 `repoURL` 설정

`argocd-apps/` 내 각 파일에서 `<YOUR_REPO_URL>`을 실제 Git 저장소 URL로 교체합니다.

### 3. ArgoCD로 배포

```bash
# 개발 환경 (자동 동기화)
argocd app create -f argocd-apps/sysdig-shield-dev.yaml

# 스테이징 환경 (자동 동기화)
argocd app create -f argocd-apps/sysdig-shield-staging.yaml

# 운영 환경 (수동 동기화)
argocd app create -f argocd-apps/sysdig-shield-production.yaml
argocd app sync sysdig-shield-production
```

### 4. 배포 확인

```bash
argocd app get sysdig-shield-dev
kubectl get pods -n sysdig-shield
```

## 저장소 구조

```
sysdig-shield-argocd/
├── argocd-apps/                      # ArgoCD Application 정의 (Helm Multi-Source)
│   ├── sysdig-shield-dev.yaml        # 개발 (자동 동기화)
│   ├── sysdig-shield-staging.yaml    # 스테이징 (자동 동기화)
│   └── sysdig-shield-production.yaml # 운영 (수동 동기화 + Lua 헬스체크)
│
├── helm-values/                      # Helm values (sysdig/shield v1.28.0)
│   ├── base-values.yaml              # 기본 설정 (모든 환경 공통)
│   ├── dev-values.yaml               # 개발 환경 오버라이드
│   ├── staging-values.yaml           # 스테이징 환경 오버라이드
│   └── production-values.yaml        # 운영 환경 오버라이드
│
├── secrets/                          # 시크릿 관리 템플릿 (평문 시크릿 없음)
│   ├── README.md
│   ├── external-secrets/             # External Secrets Operator (권장)
│   ├── sealed-secrets/               # Sealed Secrets
│   ├── argocd-vault-plugin/          # ArgoCD Vault Plugin
│   └── cert-manager/                 # TLS 인증서 관리
│
├── test/                             # 테스트 및 검증
│   ├── connectivity-test.yaml        # Sysdig 백엔드 연결 테스트
│   ├── sample-deployment.yaml        # 정상 배포 테스트
│   ├── policy-violation.yaml         # 정책 위반 테스트
│   ├── rollback-test.md              # 롤백 검증 절차
│   ├── validate-rbac.sh              # RBAC 검증 스크립트
│   └── validate-network-policies.sh  # 네트워크 정책 검증 스크립트
│
├── docs/                             # 운영 문서
│   ├── deployment-guide-kr.md        # 종합 한국어 배포 가이드
│   ├── installation.md               # 설치 및 설정 가이드
│   ├── helm-integration.md           # Helm 차트 설정 상세 가이드
│   ├── testing.md                    # 테스트 및 검증 절차
│   ├── monitoring.md                 # Prometheus/Grafana 모니터링
│   ├── maintenance.md                # 유지보수, 업그레이드, DR
│   ├── security.md                   # 보안 강화 및 인시던트 대응
│   └── troubleshooting.md            # 문제 해결
│
├── README.md
├── CLAUDE.md
└── LICENSE
```

## 배포 방식: ArgoCD Multi-Source + Helm

ArgoCD의 [Multi-Source Application](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/) 기능을 사용합니다:

- **Source 1**: `charts.sysdig.com`에서 공식 `sysdig/shield` Helm 차트
- **Source 2**: 이 Git 저장소에서 `helm-values/` values 파일

```yaml
sources:
- repoURL: https://charts.sysdig.com
  chart: shield
  targetRevision: "1.28.0"
  helm:
    valueFiles:
    - $values/helm-values/base-values.yaml
    - $values/helm-values/<ENV>-values.yaml
- repoURL: <YOUR_REPO_URL>
  targetRevision: HEAD
  ref: values
```

### 장점

- **벤더 관리**: Sysdig가 차트를 업데이트하면 `targetRevision`만 변경
- **환경 분리**: `helm-values/`에서 환경별 설정을 명확히 분리
- **단일 소스**: values 파일만 관리하면 되므로 유지보수 부담 최소화
- **GitOps**: 모든 설정 변경이 Git을 통해 추적됨

## 환경별 차이점

| 항목 | Dev | Staging | Production |
|------|-----|---------|------------|
| 동기화 방식 | 자동 | 자동 | 수동 |
| AC failurePolicy | Ignore | Ignore | Fail |
| AC dryRun | true | false | false |
| Custom Health Check | 없음 | 없음 | Lua 스크립트 |
| Slack 알림 | 있음 | 있음 | 있음 |

상세 기능별 차이는 [`docs/deployment-guide-kr.md`](docs/deployment-guide-kr.md) 2.3절을 참조하세요.

## 문서

| 문서 | 설명 |
|------|------|
| [docs/deployment-guide-kr.md](docs/deployment-guide-kr.md) | 종합 한국어 배포 가이드 |
| [docs/installation.md](docs/installation.md) | 설치 및 설정 가이드 |
| [docs/helm-integration.md](docs/helm-integration.md) | Helm 차트 설정 상세 |
| [docs/testing.md](docs/testing.md) | 테스트 및 검증 절차 |
| [docs/monitoring.md](docs/monitoring.md) | Prometheus/Grafana 모니터링 |
| [docs/maintenance.md](docs/maintenance.md) | 유지보수, 업그레이드, DR |
| [docs/security.md](docs/security.md) | 보안 강화 및 인시던트 대응 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 문제 해결 |
| [secrets/README.md](secrets/README.md) | 시크릿 관리 가이드 |

## 라이선스

MIT License — [LICENSE](LICENSE) 참조

## 참고 자료

- [Sysdig 공식 문서](https://docs.sysdig.com/)
- [Sysdig Helm Charts](https://github.com/sysdiglabs/charts)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)

---

**최종 수정**: 2026-03-31
