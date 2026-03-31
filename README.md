# Sysdig Shield ArgoCD 배포

ArgoCD를 활용한 GitOps 기반 Sysdig Shield 보안 플랫폼의 Kubernetes 클러스터 배포 저장소입니다.

## 개요

이 저장소는 **Sysdig Shield**를 배포하기 위한 ArgoCD Application 매니페스트와 Kubernetes 설정을 포함합니다. Sysdig Shield는 Kubernetes 환경을 위한 런타임 보안, 규정 준수, 위협 탐지 플랫폼입니다. ArgoCD를 통한 GitOps 방식으로 일관성 있고 감사 가능한 자동 배포를 보장합니다.

### Sysdig Shield 주요 기능

- **런타임 위협 탐지**: 실시간 보안 모니터링 및 위협 탐지
- **KSPM (Kubernetes Security Posture Management)**: 규정 준수 및 구성 모니터링
- **이미지 스캔**: 취약점 평가 및 정책 기반 검증
- **어드미션 컨트롤러**: 배포 시점 정책 제어
- **포렌식**: 상세 조사 및 대응 기능

### ArgoCD 활용 이유

- **선언적 GitOps**: 인프라/애플리케이션 정의를 Git에서 관리
- **자동 동기화**: Git 변경 사항 자동 배포
- **롤백**: 이전 버전으로 손쉬운 복구
- **멀티클러스터**: 여러 Kubernetes 클러스터 통합 관리
- **감사 추적**: 모든 변경 및 배포 이력 보존

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      Git 저장소                              │
│  (이 저장소 - 단일 진실 원본, Single Source of Truth)          │
│                                                              │
│  ├── argocd-apps/          (ArgoCD Application 정의)         │
│  ├── manifests/            (Kubernetes 매니페스트 - 참조용)    │
│  ├── helm-values/          (Helm Values)                     │
│  ├── kustomize/            (환경별 오버레이)                   │
│  ├── secrets/              (시크릿 관리 템플릿)                │
│  ├── test/                 (테스트 매니페스트 및 절차)           │
│  └── docs/                 (운영 문서)                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ GitOps 동기화
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      ArgoCD                                  │
│  - Git 저장소 모니터링                                        │
│  - 원하는 상태를 클러스터에 동기화                               │
│  - UI/CLI 관리 인터페이스 제공                                 │
│  - 동기화 이벤트에 대한 Slack 알림 전송                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ 배포
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes 클러스터                               │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │         Sysdig Shield 컴포넌트                 │           │
│  ├──────────────────────────────────────────────┤           │
│  │ • Sysdig Agent (DaemonSet)                   │           │
│  │ • Admission Controller (Deployment + HPA)    │           │
│  │ • Node Analyzer (DaemonSet)                  │           │
│  │ • KSPM Collector (Deployment)                │           │
│  └──────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## 사전 요구사항

- **Kubernetes 클러스터**: v1.24 이상, RBAC 활성화
- **ArgoCD**: v2.8 이상 설치 및 구성
- **kubectl**: 클러스터 접근 설정 완료
- **argocd CLI**: 명령줄 관리용
- **Sysdig 계정**: Sysdig Secure 구독 및 Access Key 보유

## 빠른 시작

### 1. 저장소 복제

```bash
git clone <YOUR_REPO_URL>
cd sysdig-shield-argocd
```

### 2. Sysdig Access 설정

```bash
kubectl create namespace sysdig-shield

kubectl create secret generic sysdig-agent \
  --from-literal=access-key=YOUR_SYSDIG_ACCESS_KEY \
  -n sysdig-shield
```

### 3. ArgoCD로 배포

```bash
# 개발 환경 배포 (자동 동기화)
argocd app create -f argocd-apps/sysdig-shield-dev.yaml

# 스테이징 환경 배포 (자동 동기화)
argocd app create -f argocd-apps/sysdig-shield-staging.yaml

# 운영 환경 배포 (수동 동기화)
argocd app create -f argocd-apps/sysdig-shield-production.yaml
argocd app sync sysdig-shield-production
```

### 4. 배포 확인

```bash
# ArgoCD 애플리케이션 상태 확인
argocd app get sysdig-shield-production

# 파드 상태 확인
kubectl get pods -n sysdig-shield

# 백엔드 연결 테스트
kubectl apply -f test/connectivity-test.yaml
kubectl wait --for=condition=complete job/sysdig-connectivity-test -n sysdig-shield --timeout=60s
kubectl logs -n sysdig-shield job/sysdig-connectivity-test
kubectl delete -f test/connectivity-test.yaml
```

## 저장소 구조

```
.
├── argocd-apps/                      # ArgoCD Application 정의
│   ├── sysdig-shield-base.yaml       # 베이스 템플릿
│   ├── sysdig-shield-dev.yaml        # 개발 (자동 동기화, Slack 알림)
│   ├── sysdig-shield-staging.yaml    # 스테이징 (자동 동기화, Slack 알림)
│   └── sysdig-shield-production.yaml # 운영 (수동 동기화, Lua 헬스체크)
│
├── manifests/                        # Kubernetes 매니페스트 (참조용)
│   ├── 00-namespace.yaml
│   ├── sysdig-agent/
│   ├── admission-controller/
│   ├── node-analyzer/
│   ├── kspm-collector/
│   ├── rbac/
│   └── network-policies/
│
├── helm-values/                      # Helm values 파일
│   ├── base-values.yaml              # 기본 설정 (sysdig/shield v1.28.0)
│   ├── dev-values.yaml
│   ├── staging-values.yaml
│   └── production-values.yaml
│
├── kustomize/                        # Kustomize 오버레이 (주요 배포 방식)
│   ├── base/                         # 모든 환경의 기본 설정
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── production/               # HPA, PDB 포함
│
├── secrets/                          # 시크릿 관리 템플릿 (평문 시크릿 없음)
│   ├── README.md
│   ├── external-secrets/
│   ├── sealed-secrets/
│   ├── argocd-vault-plugin/
│   └── cert-manager/
│
├── test/                             # 테스트 매니페스트 및 검증 절차
│   ├── connectivity-test.yaml
│   ├── sample-deployment.yaml
│   ├── policy-violation.yaml
│   ├── rollback-test.md
│   ├── validate-rbac.sh
│   └── validate-network-policies.sh
│
└── docs/                             # 운영 문서
    ├── deployment-guide-kr.md        # 종합 한국어 배포 가이드
    ├── installation.md               # 설치 및 설정 가이드
    ├── helm-integration.md           # Helm 차트 통합
    ├── testing.md                    # 테스트 및 검증 절차
    ├── monitoring.md                 # Prometheus/Grafana 모니터링
    ├── maintenance.md                # 유지보수, 업그레이드, DR
    ├── security.md                   # 보안 강화 및 인시던트 대응
    └── troubleshooting.md            # 문제 해결
```

## 환경별 차이점

| 항목 | Dev | Staging | Production |
|------|-----|---------|------------|
| 동기화 방식 | 자동 | 자동 | 수동 |
| Webhook failurePolicy | Ignore | Ignore | Fail |
| AC replicas | 1 | 2 | 3 (최소, HPA 3~8) |
| HPA | 없음 | 없음 | 있음 |
| PodDisruptionBudget | 없음 | 있음 | 있음 |
| Slack 알림 | 있음 | 있음 | 있음 |
| 로그 레벨 | debug | info | warning |

## 시크릿 관리

**시크릿은 절대 Git에 커밋하지 않습니다.** 다음 3가지 방식을 지원합니다:

1. **External Secrets Operator** (권장): 외부 시크릿 저장소와 연동
2. **Sealed Secrets**: 암호화된 시크릿을 Git에 저장
3. **ArgoCD Vault Plugin**: HashiCorp Vault에서 배포 시점에 주입

자세한 내용은 [`secrets/README.md`](secrets/README.md)를 참조하세요.

## 모니터링

Prometheus/Grafana를 활용한 컴포넌트 상태 모니터링:

| 컴포넌트 | 포트 | 경로 |
|----------|------|------|
| sysdig-agent | 24231 | /metrics |
| admission-controller | 8080 | /metrics |
| node-analyzer | 8080 | /metrics |
| kspm-collector | 8080 | /metrics |

상세 알림 규칙 및 Grafana 대시보드 설정은 [`docs/monitoring.md`](docs/monitoring.md)를 참조하세요.

## 문서

| 문서 | 설명 |
|------|------|
| [docs/deployment-guide-kr.md](docs/deployment-guide-kr.md) | 종합 한국어 배포 가이드 (구조 리뷰, 기능 분석, 최소 배포) |
| [docs/installation.md](docs/installation.md) | 설치 및 설정 가이드 |
| [docs/helm-integration.md](docs/helm-integration.md) | Helm 차트 통합 가이드 |
| [docs/testing.md](docs/testing.md) | 테스트 및 검증 절차 |
| [docs/monitoring.md](docs/monitoring.md) | Prometheus 메트릭, 알림 규칙, Grafana 대시보드 |
| [docs/maintenance.md](docs/maintenance.md) | 유지보수, 업그레이드, 백업/DR |
| [docs/security.md](docs/security.md) | 보안 강화 체크리스트 및 인시던트 대응 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 일반적인 문제 해결 및 진단 |
| [secrets/README.md](secrets/README.md) | 시크릿 관리 가이드 |
| [test/rollback-test.md](test/rollback-test.md) | 롤백 검증 절차 |

## 기여 방법

1. 저장소를 Fork합니다
2. 기능 브랜치를 생성합니다 (`git checkout -b feature/improvement`)
3. 변경 사항을 적용합니다
4. 개발 환경에서 테스트합니다
5. 커밋합니다 (`git commit -am '새 기능 추가'`)
6. 브랜치를 Push합니다 (`git push origin feature/improvement`)
7. Pull Request를 생성합니다

## 라이선스

이 프로젝트는 MIT 라이선스로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 참고 자료

- [Sysdig 공식 문서](https://docs.sysdig.com/)
- [Sysdig Helm Charts 저장소](https://github.com/sysdiglabs/charts)
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [Kubernetes 보안 모범 사례](https://kubernetes.io/docs/concepts/security/)
- [External Secrets Operator](https://external-secrets.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

## 지원

- **Sysdig 지원**: https://support.sysdig.com
- **커뮤니티**: Kubernetes Slack #sysdig 채널

---

**최종 수정**: 2026-03-31
