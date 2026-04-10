# Sysdig Shield ArgoCD 배포 — NodePool 기반 멀티 릴리스

ArgoCD를 활용한 GitOps 기반 Sysdig Shield 보안 플랫폼의 Kubernetes 클러스터 배포 저장소입니다.

> **이 브랜치 (KR-multi)**: Karpenter 환경에서 인스턴스 사이즈별로 에이전트 리소스를 분리하여 배포하는 **NodePool 기반 멀티 릴리스** 방식을 구현합니다. 단일 프로파일 방식은 [KR 브랜치](https://github.com/EdwardArchive/sysdig-shield-argocd/tree/KR)를 참조하세요.

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

## 고객 배포 가이드

이 저장소는 **템플릿/레퍼런스** 역할입니다. 고객 환경에 배포할 때는 아래 절차를 따릅니다.

### Step 1: 저장소 복제

고객의 Git 저장소(GitHub, GitLab 등)에 이 저장소를 Fork하거나 복사합니다:

```bash
# 방법 A: GitHub Fork
# https://github.com/EdwardArchive/sysdig-shield-argocd 에서 Fork 버튼 클릭

# 방법 B: 별도 저장소에 복사
git clone https://github.com/EdwardArchive/sysdig-shield-argocd.git
cd sysdig-shield-argocd
git remote set-url origin https://github.com/<CUSTOMER_ORG>/sysdig-shield-argocd.git
git push -u origin main
```

### Step 2: 고객 환경에 맞게 수정

```bash
# 1. helm-values/base-values.yaml — Sysdig 엔드포인트, 리전 등 수정
# 2. argocd-apps/*.yaml — repoURL을 고객 Git 저장소 URL로 변경
# 3. 환경별 values 파일 — 클러스터 이름, 리소스 제한 등 조정
```

### Step 3: 시크릿 생성 (클러스터에 직접)

```bash
kubectl create namespace sysdig-shield
kubectl create secret generic sysdig-agent \
  --from-literal=access-key=<CUSTOMER_ACCESS_KEY> \
  -n sysdig-shield
```

> 멀티 클러스터 환경에서는 [AWS SM + ESO](docs/aws-secrets-manager-guide.md)로 시크릿을 자동 관리할 수 있습니다.

### Step 4: ArgoCD Application 적용

```bash
kubectl apply -f argocd-apps/sysdig-shield-dev.yaml
```

이후 Git에 push하면 ArgoCD가 자동으로 변경을 감지하고 재배포합니다.

## 빠른 시작 (내부 테스트용)

### 1. 시크릿 설정

```bash
kubectl create namespace sysdig-shield

kubectl create secret generic sysdig-agent \
  --from-literal=access-key=YOUR_SYSDIG_ACCESS_KEY \
  -n sysdig-shield
```

### 2. ArgoCD Application의 `repoURL` 설정

`argocd-apps/` 내 각 파일에서 repoURL을 고객의 Git 저장소 URL로 교체합니다.
이 저장소를 Fork하여 사용하거나, 별도 저장소에 `helm-values/` 디렉토리를 복사합니다.

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

## 저장소 구조 (KR-multi 브랜치)

```
sysdig-shield-argocd/
├── applicationsets/                          # [신규] ApplicationSet 정의 (멀티 릴리스)
│   ├── sysdig-shield-multi-nodepool.yaml     # Git Generator + Matrix (디렉토리 기반)
│   └── sysdig-shield-cluster-generator.yaml  # Cluster Generator + Matrix (자동 감지)
│
├── argocd-apps/                              # [기존] 단일 환경별 Application (참고용)
│   ├── sysdig-shield-dev.yaml
│   ├── sysdig-shield-staging.yaml
│   └── sysdig-shield-production.yaml
│
├── helm-values/
│   ├── base-values.yaml                      # 모든 클러스터/노드그룹 공통 설정
│   ├── resource-profiles/                    # [신규] 노드 사이즈별 리소스 프로파일
│   │   ├── small.yaml                        #   2-4 vCPU (t3.medium ~ t3.xlarge)
│   │   ├── medium.yaml                       #   4-16 vCPU (m5.xlarge ~ m5.4xlarge)
│   │   └── large.yaml                        #   16+ vCPU (m5.4xlarge ~ m5.24xlarge)
│   ├── clusters/                             # [신규] 클러스터별 고유 설정
│   │   ├── example-cluster-a/
│   │   │   ├── values.yaml                   #   클러스터 공통
│   │   │   ├── values-small.yaml             #   클러스터 + small 노드그룹 고유
│   │   │   ├── values-medium.yaml
│   │   │   └── values-large.yaml
│   │   └── example-cluster-b/
│   │       ├── values.yaml
│   │       ├── values-small.yaml
│   │       ├── values-medium.yaml
│   │       └── values-large.yaml
│   ├── dev-values.yaml                       # [기존] 단일 릴리스 환경별 (참고용)
│   ├── staging-values.yaml
│   ├── production-values.yaml
│   └── minikube-values.yaml
│
├── karpenter-examples/                       # [신규] Karpenter NodePool 예시
│   ├── nodepool-small.yaml
│   ├── nodepool-medium.yaml
│   └── nodepool-large.yaml
│
├── scripts/                                  # [신규] 운영 자동화 스크립트
│   └── add-cluster.sh                        #   새 클러스터 추가 템플릿 생성
│
├── secrets/                                  # 시크릿 관리 템플릿
├── test/                                     # 테스트 및 검증
├── docs/                                     # 운영 문서
├── README.md
├── CLAUDE.md
└── LICENSE
```

## 핵심 개념: NodePool 기반 멀티 릴리스

### 왜 멀티 릴리스가 필요한가

Karpenter 환경에서는 `t3.medium`(2 vCPU/4GB)부터 `m5.8xlarge`(32 vCPU/128GB)까지 다양한 인스턴스가 하나의 클러스터에 공존합니다. Sysdig Shield의 Host Shield는 DaemonSet이므로 모든 노드에 동일한 리소스를 할당하는데, 이는 작은 노드에서는 과다 할당, 큰 노드에서는 과소 할당 문제를 발생시킵니다.

### 동작 원리

1. Karpenter NodePool에 `node-size-class: small|medium|large` 라벨을 부여
2. 각 리소스 프로파일(`resource-profiles/*.yaml`)에서 해당 라벨의 `nodeSelector`와 적정 리소스를 설정
3. ApplicationSet의 Matrix Generator가 클러스터 × 노드그룹 조합을 자동 생성
4. 각 조합별로 별도 네임스페이스(`sysdig-shield-small`, `sysdig-shield-medium`, `sysdig-shield-large`)에 배포

### Cluster Shield 중복 배포 방지

Host Shield(DaemonSet)는 노드그룹별로 분리 배포해도 문제없지만, Cluster Shield(Deployment)는 클러스터당 1개만 필요합니다. 따라서 `small` 프로파일에서만 `cluster.enabled: true`, 나머지는 `false`로 설정합니다.

### Values 덮어쓰기 순서

```
1. base-values.yaml                              ← 공통 설정
2. resource-profiles/{size}.yaml                  ← 노드그룹 리소스 + nodeSelector
3. clusters/{cluster-name}/values.yaml            ← 클러스터 공통
4. clusters/{cluster-name}/values-{size}.yaml     ← 클러스터+노드그룹 고유 (final)
```

### 새 클러스터 추가 방법

```bash
# 1. 스크립트로 템플릿 생성
./scripts/add-cluster.sh my-new-cluster

# 2. values.yaml에서 environment, team 등 수정
vim helm-values/clusters/my-new-cluster/values.yaml

# 3. Git push → ArgoCD 자동 감지 → Shield 배포
git add . && git commit -m "Add my-new-cluster" && git push
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
- repoURL: https://github.com/EdwardArchive/sysdig-shield-argocd.git
  targetRevision: main
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
| [docs/aws-secrets-manager-guide.md](docs/aws-secrets-manager-guide.md) | AWS SM + ESO 시크릿 관리 |
| [docs/illumio-minikube-network-issue.md](docs/illumio-minikube-network-issue.md) | Illumio + minikube 네트워크 분석 |
| [secrets/README.md](secrets/README.md) | 시크릿 관리 가이드 |
| [test/rollback-test.md](test/rollback-test.md) | 롤백 검증 절차 |

## 라이선스

MIT License — [LICENSE](LICENSE) 참조

## 참고 자료

- [Sysdig 공식 문서](https://docs.sysdig.com/)
- [Sysdig Helm Charts](https://github.com/sysdiglabs/charts)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)

---

**최종 수정**: 2026-03-31
