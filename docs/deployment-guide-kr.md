# Sysdig Shield ArgoCD 배포 가이드

> **버전**: 1.0.0
> **최종 수정**: 2026-03-31
> **기반 차트**: sysdig/shield v1.28.0

---

## 목차

- [1. 저장소 구조 리뷰](#1-저장소-구조-리뷰)
  - [1.1 디렉토리 구조](#11-디렉토리-구조)
  - [1.2 핵심 컴포넌트](#12-핵심-컴포넌트)
  - [1.3 배포 방식 비교](#13-배포-방식-비교)
  - [1.4 Sync Wave 순서](#14-sync-wave-순서)
- [2. 기능 분석](#2-기능-분석)
  - [2.1 보안 기능](#21-보안-기능)
  - [2.2 인프라 기능](#22-인프라-기능)
  - [2.3 환경별 차이점 비교표](#23-환경별-차이점-비교표)
- [3. 오류 및 개선사항 분석](#3-오류-및-개선사항-분석)
- [4. 최소 ArgoCD Agent 배포 가이드](#4-최소-argocd-agent-배포-가이드)
  - [4.1 사전 요구사항](#41-사전-요구사항)
  - [4.2 최소 디렉토리 구조](#42-최소-디렉토리-구조)
  - [4.3 단계별 배포](#43-단계별-배포)
  - [4.4 ArgoCD Application 매니페스트](#44-argocd-application-매니페스트)
  - [4.5 배포 확인](#45-배포-확인)
- [5. 테스트 방법](#5-테스트-방법)
  - [5.1 배포 전 검증](#51-배포-전-검증)
  - [5.2 배포 후 검증](#52-배포-후-검증)
  - [5.3 연결 테스트](#53-연결-테스트)
  - [5.4 보안 정책 테스트](#54-보안-정책-테스트)
  - [5.5 검증 스크립트](#55-검증-스크립트)
  - [5.6 환경별 테스트 체크리스트](#56-환경별-테스트-체크리스트)
- [부록 A: 주요 파일 경로 참조표](#부록-a-주요-파일-경로-참조표)
- [부록 B: 트러블슈팅 요약](#부록-b-트러블슈팅-요약)

---

## 1. 저장소 구조 리뷰

### 1.1 디렉토리 구조

```
sysdig-shield-argocd/
├── argocd-apps/                          # ArgoCD Application 매니페스트
│   ├── sysdig-shield-base.yaml           #   베이스 (수동 동기화)
│   ├── sysdig-shield-dev.yaml            #   개발 환경 (자동 동기화)
│   ├── sysdig-shield-staging.yaml        #   스테이징 환경 (자동 동기화)
│   └── sysdig-shield-production.yaml     #   운영 환경 (수동 동기화 + Lua 헬스체크)
│
├── helm-values/                          # Helm 차트 values 파일
│   ├── base-values.yaml                  #   기본 설정 (sysdig/shield v1.28.0)
│   ├── dev-values.yaml                   #   개발 환경 오버라이드
│   ├── staging-values.yaml               #   스테이징 환경 오버라이드
│   └── production-values.yaml            #   운영 환경 오버라이드
│
├── kustomize/                            # Kustomize 기반 배포 (주요 배포 방식)
│   ├── base/                             #   기본 리소스 정의
│   │   ├── kustomization.yaml            #     Sync Wave별 리소스 정렬
│   │   ├── 00-namespace.yaml             #     네임스페이스 (Wave 0)
│   │   ├── rbac/                         #     RBAC 리소스 12개 (Wave 1)
│   │   ├── sysdig-agent/                 #     Agent ConfigMap + DaemonSet
│   │   ├── admission-controller/         #     AC 관련 리소스 5개
│   │   ├── node-analyzer/                #     Node Analyzer ConfigMap + DaemonSet
│   │   ├── kspm-collector/               #     KSPM Collector ConfigMap + Deployment
│   │   └── network-policies/             #     네트워크 정책 7개
│   └── overlays/
│       ├── dev/                          #   개발: 리소스 축소, PDB 제거, AC 1 replica
│       ├── staging/                      #   스테이징: 중간 리소스, AC 2 replicas
│       └── production/                   #   운영: 고성능, HPA, PDB, AC 3+ replicas
│
├── manifests/                            # Raw Kubernetes 매니페스트 (레거시/참조용)
│   ├── 00-namespace.yaml
│   ├── rbac/                             #   RBAC 리소스 12개
│   ├── sysdig-agent/                     #   Agent ConfigMap + DaemonSet
│   ├── admission-controller/             #   AC 리소스 6개 (HPA 포함)
│   ├── node-analyzer/                    #   Node Analyzer 리소스 2개
│   ├── kspm-collector/                   #   KSPM Collector 리소스 2개
│   └── network-policies/                 #   네트워크 정책 7개
│
├── secrets/                              # 시크릿 관리 템플릿
│   ├── README.md                         #   시크릿 관리 가이드
│   ├── external-secrets/                 #   External Secrets Operator (권장)
│   ├── sealed-secrets/                   #   Sealed Secrets
│   ├── argocd-vault-plugin/              #   ArgoCD Vault Plugin
│   └── cert-manager/                     #   TLS 인증서 관리
│
├── test/                                 # 테스트 및 검증
│   ├── connectivity-test.yaml            #   Sysdig 백엔드 연결 테스트 Job
│   ├── sample-deployment.yaml            #   정상 배포 테스트 (nginx)
│   ├── policy-violation.yaml             #   정책 위반 테스트 (AC 차단 확인)
│   ├── rollback-test.md                  #   롤백 절차 문서
│   ├── validate-rbac.sh                  #   RBAC 검증 스크립트
│   └── validate-network-policies.sh      #   네트워크 정책 검증 스크립트
│
├── docs/                                 # 운영 문서
│   ├── installation.md                   #   설치 가이드
│   ├── configuration.md                  #   설정 참조
│   ├── helm-integration.md               #   Helm 차트 통합 가이드
│   ├── testing.md                        #   테스트 절차
│   ├── security.md                       #   보안 강화 체크리스트
│   ├── monitoring.md                     #   모니터링 (Prometheus/Grafana)
│   ├── troubleshooting.md                #   문제 해결
│   ├── upgrade.md                        #   업그레이드 절차
│   ├── maintenance.md                    #   유지보수 및 DR
│   └── incident-response.md              #   인시던트 대응
│
├── openspec/                             # 설계 명세 문서
│   ├── specs/                            #   컴포넌트별 스펙 10개
│   └── changes/archive/                  #   변경 이력 아카이브
│
├── README.md                             # 프로젝트 개요
├── CLAUDE.md                             # Claude Code 작업 가이드
└── LICENSE                               # MIT 라이선스
```

### 1.2 핵심 컴포넌트

#### Sysdig Agent (DaemonSet)
- **역할**: 모든 노드에서 런타임 보안 모니터링 수행
- **배포 유형**: DaemonSet (모든 노드에 1개씩)
- **주요 특성**:
  - `hostNetwork: true`, `hostPID: true`, `hostIPC: true` — 호스트 레벨 모니터링 필요
  - `privileged: true` + SYS_ADMIN, SYS_PTRACE 등 capability 부여
  - 컨테이너 런타임 소켓 마운트 (Docker, containerd, CRI-O)
  - `/host/proc`, `/host/dev`, `/host/boot` 등 호스트 파일시스템 마운트
  - collector.sysdigcloud.com:6443 으로 데이터 전송
- **리소스 기본값**: CPU 500m~1000m, Memory 512Mi~1Gi
- **파일**: `kustomize/base/sysdig-agent/daemonset.yaml`, `configmap.yaml`

#### Admission Controller (Deployment)
- **역할**: 배포 시점에 보안 정책을 검증하고 위반 시 차단
- **배포 유형**: Deployment (환경별 1~8 replicas)
- **주요 특성**:
  - ValidatingWebhookConfiguration을 통해 API 서버와 연동
  - 웹훅 포트 8443, 메트릭 포트 8080
  - `failurePolicy`: dev/staging은 `Ignore`, production은 `Fail`
  - 이미지 취약점 스캔 및 정책 위반 감지
  - 컨테이너 수준 보안 컨텍스트 강제
- **파일**: `kustomize/base/admission-controller/` 디렉토리 내 5개 파일

#### Node Analyzer (DaemonSet)
- **역할**: 노드 레벨 이미지 스캔 및 취약점 분석
- **배포 유형**: DaemonSet
- **주요 특성**:
  - 호스트의 컨테이너 이미지를 로컬에서 스캔
  - 호스트 취약점 관리 (Host Vulnerability Management)
  - 리소스 사용량은 Agent보다 적음
- **파일**: `kustomize/base/node-analyzer/configmap.yaml`, `daemonset.yaml`

#### KSPM Collector (Deployment)
- **역할**: Kubernetes 보안 태세 관리 (Security Posture Management)
- **배포 유형**: Deployment (단일 인스턴스)
- **주요 특성**:
  - 클러스터 구성 및 규정 준수 데이터 수집
  - CIS Benchmarks, 보안 모범 사례 검증
  - 클러스터 및 호스트 수준 포스처 분석
- **파일**: `kustomize/base/kspm-collector/configmap.yaml`, `deployment.yaml`

### 1.3 배포 방식 비교

이 저장소는 4가지 배포 방식을 지원합니다:

| 방식 | 디렉토리 | 특징 | 권장 대상 |
|------|----------|------|-----------|
| **ArgoCD + Kustomize** | `argocd-apps/` + `kustomize/` | GitOps, 환경별 오버레이, Sync Wave | 운영 환경 (권장) |
| **Helm** | `helm-values/` | sysdig/shield 공식 차트, 기능 토글 | Helm 기반 팀 |
| **Kustomize Only** | `kustomize/` | `kubectl apply -k` 직접 적용 | ArgoCD 없는 환경 |
| **Raw Manifests** | `manifests/` | 단순 `kubectl apply` | 참조/테스트용 |

**ArgoCD Application 구조** (`argocd-apps/sysdig-shield-dev.yaml` 예시):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sysdig-shield-dev
  namespace: argocd
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: sysdig-deployments
    notifications.argoproj.io/subscribe.on-sync-failed.slack: sysdig-alerts
    notifications.argoproj.io/subscribe.on-health-degraded.slack: sysdig-alerts
spec:
  project: default
  source:
    repoURL: https://github.com/yourusername/sysdig-shield-argocd.git
    targetRevision: HEAD
    path: kustomize/overlays/dev    # 각 환경별 오버레이 경로 지정
  destination:
    server: https://kubernetes.default.svc
    namespace: sysdig-shield
  syncPolicy:
    automated:                       # 개발/스테이징: 자동 동기화
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jsonPointers:
    - /webhooks/0/clientConfig/caBundle
```

### 1.4 Sync Wave 순서

ArgoCD Sync Wave를 통해 리소스가 의존성 순서대로 배포됩니다 (`kustomize/base/kustomization.yaml` 기준):

| Wave | 리소스 | 설명 |
|------|--------|------|
| **0** | Namespace (`sysdig-shield`) | 모든 리소스의 기반 네임스페이스 |
| **1** | RBAC (12개 리소스) | ServiceAccount, ClusterRole, ClusterRoleBinding × 4 컴포넌트 |
| **2** | ConfigMap (4개) + NetworkPolicy (7개) | Agent/AC/NA/KSPM 설정 + 네트워크 격리 |
| **3** | DaemonSet (2개) | Sysdig Agent + Node Analyzer |
| **4** | Deployment + Service + PDB | Admission Controller + KSPM Collector |
| **5** | ValidatingWebhookConfiguration | AC가 준비된 후 웹훅 등록 |

---

## 2. 기능 분석

### 2.1 보안 기능

#### 런타임 보안 (Runtime Security)
- **위협 탐지**: Sysdig Agent가 syscall 레벨에서 실시간 위협 탐지
- **Drift Control**: 컨테이너 실행 후 파일 변경 감지 및 차단
- **Malware Control**: 실시간 악성코드 탐지
- **ML Policies**: 머신러닝 기반 이상 행위 탐지 (운영 환경에서만 활성화)
- **Kubernetes Audit**: K8s 감사 로그 분석 (포트 6443, 타임아웃 10초)

#### 어드미션 컨트롤 (Admission Control)
- ValidatingWebhookConfiguration을 통한 배포 시점 정책 검증
- **컨테이너 취약점 관리**: 이미지 스캔 결과 기반 배포 허용/차단
- **포스처 검증**: 보안 설정 준수 여부 확인
- **제외 네임스페이스**: kube-system, kube-public, kube-node-lease, sysdig-shield
- 환경별 정책:
  - Dev: `dryRun=true` (로그만 기록, 차단 안 함)
  - Staging: `failurePolicy=Ignore` (실패 시 통과)
  - Production: `failurePolicy=Fail` (실패 시 차단)

#### 취약점 관리 (Vulnerability Management)
- **컨테이너 취약점**: Node Analyzer를 통한 이미지 스캔
- **호스트 취약점**: 노드 OS 레벨 취약점 탐지
- **In-Use 취약점**: 실제 실행 중인 패키지의 취약점만 추적 (오탐 감소)

#### KSPM (Kubernetes Security Posture Management)
- **클러스터 포스처**: 클러스터 구성 보안 모범 사례 검증
- **호스트 포스처**: 노드 수준 보안 설정 검증
- CIS Benchmark 기반 규정 준수 확인

### 2.2 인프라 기능

#### 네트워크 정책 (Network Policies)
7개의 NetworkPolicy로 트래픽 격리:

| 정책 | 유형 | 대상 |
|------|------|------|
| `default-deny-all` | Ingress + Egress | 전체 네임스페이스 |
| `sysdig-agent-egress` | Egress | Agent → Sysdig 백엔드 |
| `admission-controller-ingress` | Ingress | API Server → AC |
| `admission-controller-egress` | Egress | AC → Sysdig 백엔드 |
| `node-analyzer-egress` | Egress | NA → Sysdig 백엔드 |
| `kspm-collector-egress` | Egress | KSPM → Sysdig 백엔드 |
| `dns-egress` | Egress | 전체 → DNS (UDP/TCP 53) |

#### RBAC
4개 컴포넌트 각각에 대해 ServiceAccount + ClusterRole + ClusterRoleBinding = 총 12개 RBAC 리소스.

Agent ClusterRole 주요 권한 (`manifests/rbac/sysdig-agent-clusterrole.yaml`):
- `""` (core): pods, nodes, namespaces, services, endpoints, replicationcontrollers, persistentvolumes 등 — get/list/watch
- `""` (events): get/list/watch/**create**
- `apps`: deployments, daemonsets, replicasets, statefulsets — get/list/watch
- `batch`: jobs, cronjobs — get/list/watch
- `networking.k8s.io`: networkpolicies, ingresses — get/list/watch
- `metrics.k8s.io`: pods, nodes — get/list

#### 시크릿 관리
3가지 방식 지원 (`secrets/` 디렉토리):

| 방식 | 파일 | 권장 대상 |
|------|------|-----------|
| External Secrets Operator | `external-secrets/*.yaml` | AWS/Vault/GCP 사용 조직 (권장) |
| Sealed Secrets | `sealed-secrets/sealed-secret-example.yaml` | 소규모 배포 |
| ArgoCD Vault Plugin | `argocd-vault-plugin/secret-with-placeholders.yaml` | HashiCorp Vault 사용 조직 |

필수 시크릿:
- `sysdig-agent`: Sysdig 백엔드 Access Key
- `sysdig-admission-controller-tls`: AC 웹훅 TLS 인증서

### 2.3 환경별 차이점 비교표

Helm values (`helm-values/`) 및 Kustomize overlays (`kustomize/overlays/`) 기준:

| 항목 | Dev | Staging | Production |
|------|-----|---------|------------|
| **ArgoCD 동기화** | 자동 (prune + selfHeal) | 자동 (prune + selfHeal) | **수동** |
| **Custom Health Check** | 없음 | 없음 | Lua 스크립트 (DaemonSet/Deployment) |
| **Slack 알림** | 있음 | 있음 | 있음 |
| **AC Replicas** | 1 | 2 | 3 (min), HPA 3~8 |
| **AC failurePolicy** | Ignore | Ignore | **Fail** |
| **AC dryRun** | **true** | false | false |
| **HPA** | 없음 | 없음 | CPU 70% / Memory 80% |
| **PDB** | 제거 | 기본 (minAvailable: 1) | 기본 (minAvailable: 1) |
| **로그 레벨** | debug | info | warning |
| **Agent CPU (req/limit)** | 100m / 500m | 패치 적용 | 500m / 1000m |
| **Agent Memory (req/limit)** | 256Mi / 512Mi | 패치 적용 | 512Mi / 1Gi |
| **Host Posture** | 비활성 | 활성 | 활성 |
| **Host Vulnerability** | 비활성 | 활성 | 활성 |
| **Drift Control** | 비활성 | 활성 | 활성 |
| **Malware Control** | 비활성 | 활성 | 활성 |
| **ML Policies** | 비활성 | 비활성 (base 상속) | **활성** |
| **K8s Audit** | 비활성 | 활성 | 활성 |
| **Activity Audit** | 비활성 | 활성 | 활성 |
| **Rapid Response** | 비활성 | 활성 | 활성 |
| **Supply Chain Security** | 없음 | 없음 | 활성 (image signature 별도) |

---

## 3. 오류 및 개선사항 분석

### 3.1 플레이스홀더 GitHub URL (Critical)

**위치**: `argocd-apps/` 내 모든 4개 파일
**내용**: `repoURL` 값이 `https://github.com/yourusername/sysdig-shield-argocd.git`으로 설정됨
**영향**: ArgoCD Application을 그대로 적용하면 리포지토리를 찾을 수 없어 동기화 실패
**해결**: 실제 Git 리포지토리 URL로 교체 필요

### 3.2 manifests/ vs kustomize/base/ 불일치 (High)

**Admission Controller ConfigMap 차이**:
- `manifests/admission-controller/configmap.yaml`에는 `auditLog` 섹션이 포함되어 있으나, `kustomize/base/admission-controller/configmap.yaml`에는 누락됨
- 누락된 설정:
  ```yaml
  auditLog:
    enabled: true
    path: /var/log/sysdig/admission-controller-audit.log
    maxSizeMB: 100
    maxBackups: 5
    includeRequestObject: true
    includeResponseObject: false
  ```

**HPA 파라미터 불일치**:
- `manifests/admission-controller/hpa.yaml`: minReplicas=2, maxReplicas=6
- `kustomize/overlays/production/hpa.yaml`: minReplicas=3, maxReplicas=8
- 서로 다른 스케일링 정책을 나타내며 어느 것이 정확한지 불명확

### 3.3 Base ConfigMap 하드코딩 (Medium)

**위치**: `kustomize/base/sysdig-agent/configmap.yaml` 27~30행
**내용**: `tags` 필드에 `env:production`이 하드코딩됨
**영향**: dev/staging 오버레이에서 별도 패치로 오버라이드하고 있으나, 베이스가 환경 중립적이어야 함
**해결**: 베이스의 태그를 `env:base` 또는 환경 변수 참조로 변경 권장

### 3.4 문서 참조 오류 (Low)

**위치**: `docs/installation.md` 등에서 `secrets-management.md` 파일 참조
**실제**: 해당 파일은 존재하지 않으며, 시크릿 관리 문서는 `secrets/README.md`에 위치
**해결**: 문서 내 링크를 `../secrets/README.md`로 수정

### 3.5 인시던트 대응 문서 플레이스홀더 (Low)

**위치**: `docs/incident-response.md` 3~4행
**내용**: Platform Team, Security Team 연락처가 `[contact-info]` 플레이스홀더로 남아있음
**해결**: 실제 담당팀 연락처로 교체 필요

### 3.6 Helm Values 리소스 미지정 (Medium)

**위치**: `helm-values/` 내 모든 values 파일
**내용**: CPU/Memory 리소스 requests/limits가 Helm values에 지정되어 있지 않음
**영향**: Helm 단독 배포 시 리소스 제한 없이 실행될 위험 (Kustomize 배포 시에는 오버레이 패치로 적용됨)
**해결**: Helm values에도 환경별 리소스 제한 추가 권장

### 3.7 ML Policies 환경 간 불일치 (Low)

**내용**:
- `base-values.yaml`: `ml_policies.enabled: false`
- `staging-values.yaml`: ml_policies 오버라이드 없음 → false 상속
- `production-values.yaml`: `ml_policies.enabled: true`
- Staging에서 ML Policies 테스트 없이 바로 Production에서 활성화하는 구조
**해결**: Staging에서도 ML Policies를 활성화하여 사전 검증하거나, 의도적인 결정이라면 문서화 필요

### 3.8 manifests/ 디렉토리 동기화 문제 (Medium)

**내용**: `manifests/` 디렉토리가 `kustomize/base/`와 동기화되지 않은 상태
- ArgoCD Application은 모두 `kustomize/overlays/` 경로를 참조하고 있어 `manifests/`는 실제 배포에 사용되지 않음
- HPA가 `manifests/`에만 존재하고 kustomize base에는 없음 (production overlay에서만 추가)
- ConfigMap, 태그, 로그 레벨 등에서 차이가 있음
**해결**: manifests/ 디렉토리를 제거하거나 "참조용(Reference Only)" 명시 필요

---

## 4. 최소 ArgoCD Agent 배포 가이드

전체 Sysdig Shield를 배포하지 않고 **Agent만** 최소한으로 배포하는 방법입니다.

### 4.1 사전 요구사항

- Kubernetes 클러스터 v1.24 이상 (RBAC 활성화)
- ArgoCD v2.8 이상 설치 및 접근 가능
- `kubectl`, `argocd` CLI 설정 완료
- Sysdig 계정 및 Access Key 보유

### 4.2 최소 디렉토리 구조

```
sysdig-agent-minimal/
├── 00-namespace.yaml
├── rbac/
│   ├── serviceaccount.yaml
│   ├── clusterrole.yaml
│   └── clusterrolebinding.yaml
├── configmap.yaml
├── daemonset.yaml
└── kustomization.yaml         # (선택) Kustomize 사용 시
```

필요한 리소스는 **5개**입니다:
1. Namespace
2. RBAC (ServiceAccount + ClusterRole + ClusterRoleBinding)
3. Secret (Access Key — 별도 생성)
4. ConfigMap (Agent 설정)
5. DaemonSet (Agent 파드)

### 4.3 단계별 배포

#### Step 1: Namespace 생성

```yaml
# 00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sysdig-shield
  labels:
    name: sysdig-shield
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

> Pod Security Standards에서 `privileged` 레벨이 필요합니다. Agent가 호스트 레벨 모니터링을 위해 privileged 컨테이너로 실행되기 때문입니다.

#### Step 2: RBAC 설정

```yaml
# rbac/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sysdig-agent
  namespace: sysdig-shield
```

```yaml
# rbac/clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sysdig-agent
rules:
- apiGroups: [""]
  resources:
  - pods
  - nodes
  - namespaces
  - services
  - endpoints
  - replicationcontrollers
  - persistentvolumes
  - persistentvolumeclaims
  - resourcequotas
  - limitranges
  verbs: [get, list, watch]
- apiGroups: [""]
  resources: [events]
  verbs: [get, list, watch, create]
- apiGroups: [apps]
  resources: [deployments, daemonsets, replicasets, statefulsets]
  verbs: [get, list, watch]
- apiGroups: [batch]
  resources: [jobs, cronjobs]
  verbs: [get, list, watch]
- apiGroups: [networking.k8s.io]
  resources: [networkpolicies, ingresses]
  verbs: [get, list, watch]
- apiGroups: [metrics.k8s.io]
  resources: [pods, nodes]
  verbs: [get, list]
```

```yaml
# rbac/clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sysdig-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: sysdig-agent
subjects:
- kind: ServiceAccount
  name: sysdig-agent
  namespace: sysdig-shield
```

#### Step 3: Secret 생성 (CLI)

```bash
kubectl create secret generic sysdig-agent \
  --from-literal=access-key=<YOUR_SYSDIG_ACCESS_KEY> \
  -n sysdig-shield
```

> Secret은 Git에 커밋하지 않습니다. External Secrets Operator 또는 Sealed Secrets 사용을 권장합니다. 자세한 내용은 `secrets/README.md`를 참조하세요.

#### Step 4: ConfigMap (최소 Agent 설정)

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sysdig-agent
  namespace: sysdig-shield
data:
  dragent.yaml: |
    collector: collector.sysdigcloud.com
    collector_port: 6443
    ssl: true

    log:
      console_priority: info
      file_priority: info

    tags:
      - component:sysdig-agent
      - managed-by:argocd

    security:
      enabled: true

    k8s_cluster_name: "my-cluster"

    feature:
      mode: secure
```

> `collector` 값은 리전에 따라 변경합니다:
> - US1: `collector.sysdigcloud.com` (기본값)
> - US2: `collector.us2.sysdig.com`
> - EU1: `collector.eu1.sysdig.com`
> - AU1: `collector.au1.sysdig.com`

#### Step 5: DaemonSet (Agent)

```yaml
# daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sysdig-agent
  namespace: sysdig-shield
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: sysdig-agent
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: sysdig-agent
    spec:
      serviceAccountName: sysdig-agent
      hostNetwork: true
      hostPID: true
      hostIPC: true
      dnsPolicy: ClusterFirstWithHostNet

      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
      - effect: NoExecute
        key: node.kubernetes.io/not-ready
        operator: Exists
      - effect: NoExecute
        key: node.kubernetes.io/unreachable
        operator: Exists

      containers:
      - name: sysdig-agent
        image: quay.io/sysdig/agent:latest
        imagePullPolicy: Always
        securityContext:
          privileged: true
          capabilities:
            add:
            - SYS_ADMIN
            - SYS_RESOURCE
            - SYS_PTRACE
            - SYS_CHROOT
            - NET_RAW
            - NET_ADMIN
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        env:
        - name: SYSDIG_AGENT_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: sysdig-agent
              key: access-key
        - name: COLLECTOR
          value: "collector.sysdigcloud.com"
        - name: COLLECTOR_PORT
          value: "6443"
        - name: SECURE
          value: "true"
        - name: K8S_NODE
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        readinessProbe:
          exec:
            command: [test, -e, /opt/draios/logs/running]
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          exec:
            command: [test, -e, /opt/draios/logs/running]
          initialDelaySeconds: 60
          periodSeconds: 10
        volumeMounts:
        - name: docker-sock
          mountPath: /host/var/run/docker.sock
        - name: containerd-sock
          mountPath: /host/run/containerd/containerd.sock
        - name: dev-vol
          mountPath: /host/dev
        - name: proc-vol
          mountPath: /host/proc
          readOnly: true
        - name: boot-vol
          mountPath: /host/boot
          readOnly: true
        - name: modules-vol
          mountPath: /host/lib/modules
          readOnly: true
        - name: usr-vol
          mountPath: /host/usr
          readOnly: true
        - name: run-vol
          mountPath: /host/run
        - name: sysdig-agent-config
          mountPath: /opt/draios/etc/kubernetes/config
        - name: osrel
          mountPath: /host/etc/os-release
          readOnly: true

      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
      - name: containerd-sock
        hostPath:
          path: /run/containerd/containerd.sock
          type: Socket
      - name: dev-vol
        hostPath:
          path: /dev
      - name: proc-vol
        hostPath:
          path: /proc
      - name: boot-vol
        hostPath:
          path: /boot
      - name: modules-vol
        hostPath:
          path: /lib/modules
      - name: usr-vol
        hostPath:
          path: /usr
      - name: run-vol
        hostPath:
          path: /run
      - name: osrel
        hostPath:
          path: /etc/os-release
          type: File
      - name: sysdig-agent-config
        configMap:
          name: sysdig-agent
          optional: true
```

### 4.4 ArgoCD Application 매니페스트

위 리소스들을 Git 리포지토리에 커밋한 후, 아래 ArgoCD Application을 적용합니다:

```yaml
# argocd-app-sysdig-agent.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sysdig-agent
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_ORG>/sysdig-agent-minimal.git  # 실제 URL로 교체
    targetRevision: HEAD
    path: .    # 리포지토리 루트 또는 매니페스트 경로
  destination:
    server: https://kubernetes.default.svc
    namespace: sysdig-shield
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
```

**배포 커맨드:**

```bash
# ArgoCD CLI로 적용
argocd app create -f argocd-app-sysdig-agent.yaml

# 또는 kubectl로 직접 적용
kubectl apply -f argocd-app-sysdig-agent.yaml
```

### 4.5 배포 확인

```bash
# ArgoCD 상태 확인
argocd app get sysdig-agent

# 파드 상태 확인
kubectl get pods -n sysdig-shield -l app.kubernetes.io/name=sysdig-agent

# 모든 노드에 Agent가 배포되었는지 확인
kubectl get daemonset sysdig-agent -n sysdig-shield

# Agent 로그 확인
kubectl logs -f daemonset/sysdig-agent -n sysdig-shield

# Agent 프로세스 상태 확인 (readiness 파일 존재 여부)
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- ls /opt/draios/logs/running
```

**최소 배포 vs 전체 배포 비교:**

| 항목 | 최소 배포 (Agent Only) | 전체 배포 (Shield) |
|------|------------------------|-------------------|
| 리소스 수 | 5개 | 33개+ |
| 런타임 보안 | O | O |
| 어드미션 컨트롤 | X | O |
| 이미지 스캔 | X | O (Node Analyzer) |
| KSPM | X | O |
| 네트워크 정책 | X | O (7개) |
| 웹훅 정책 | X | O |
| HPA/PDB | X | O (운영 환경) |

---

## 5. 테스트 방법

### 5.1 배포 전 검증

#### 매니페스트 dry-run 검증

```bash
# Kubernetes API 서버를 통한 dry-run
kubectl apply -f manifests/ --dry-run=server --recursive

# Kustomize 빌드 확인
kubectl kustomize kustomize/overlays/dev/
kubectl kustomize kustomize/overlays/staging/
kubectl kustomize kustomize/overlays/production/
```

#### Helm template 검증

```bash
# Helm 차트 추가
helm repo add sysdig https://charts.sysdig.com
helm repo update

# 템플릿 렌더링 (실제 배포 없이 YAML 확인)
helm template sysdig-shield sysdig/shield \
  -f helm-values/base-values.yaml \
  -f helm-values/dev-values.yaml \
  --namespace sysdig-shield \
  --debug
```

#### ArgoCD Application 검증

```bash
# ArgoCD manifest 검증 (실제 생성 없이)
argocd app create -f argocd-apps/sysdig-shield-dev.yaml --validate --dry-run
```

### 5.2 배포 후 검증

```bash
# 1. 모든 파드가 Running 상태인지 확인
kubectl get pods -n sysdig-shield

# 2. DaemonSet이 모든 노드에 배포되었는지 확인
kubectl get daemonset -n sysdig-shield

# 3. Agent 연결 상태 확인 (로그에서 "connected" 메시지 확인)
kubectl logs daemonset/sysdig-agent -n sysdig-shield | grep -i "connected\|error\|failed"

# 4. 파드 준비 상태 대기 (최대 5분)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=sysdig-agent \
  -n sysdig-shield \
  --timeout=300s

# 5. ArgoCD 동기화 상태 확인
argocd app get sysdig-shield-dev
```

### 5.3 연결 테스트

저장소에 포함된 연결 테스트 Job을 사용합니다 (`test/connectivity-test.yaml`):

```bash
# 연결 테스트 실행
kubectl apply -f test/connectivity-test.yaml

# 결과 확인 (DNS 확인, HTTPS 연결, Collector 연결)
kubectl logs -n sysdig-shield job/sysdig-connectivity-test

# 정리
kubectl delete -f test/connectivity-test.yaml
```

이 Job은 다음을 검증합니다:
- Sysdig API 서버 DNS 해석
- HTTPS 연결 (리전별 엔드포인트)
- Collector 연결 (데이터 전송 경로)

지원되는 리전: `us1`, `us2`, `us3`, `us4`, `eu1`, `au1`, `me2`

특정 리전을 테스트하려면 Secret에 `region` 키를 추가하거나 YAML을 수정합니다.

### 5.4 보안 정책 테스트

#### 정상 배포 테스트

```bash
# 정상적인 nginx 배포 (차단되지 않아야 함)
kubectl apply -f test/sample-deployment.yaml --dry-run=server

# 실제 배포 후 정리
kubectl apply -f test/sample-deployment.yaml
kubectl delete -f test/sample-deployment.yaml
```

#### 정책 위반 테스트

`test/policy-violation.yaml`에는 의도적인 보안 위반이 포함되어 있습니다:

```yaml
# 위반 사항:
# - hostNetwork: true
# - hostPID: true
# - nginx:1.14 (취약한 이전 버전)
# - privileged: true
# - runAsUser: 0 (root)
```

```bash
# Admission Controller가 차단하는지 확인 (dry-run)
kubectl apply -f test/policy-violation.yaml --dry-run=server

# 예상 결과:
# - Dev: dryRun=true이므로 경고만 출력, 배포 허용
# - Staging: failurePolicy=Ignore이므로 AC 오류 시에도 통과, 정상 동작 시 차단
# - Production: failurePolicy=Fail이므로 반드시 차단
```

### 5.5 검증 스크립트

#### RBAC 검증 (`test/validate-rbac.sh`)

```bash
# 실행
bash test/validate-rbac.sh

# 검증 항목:
# 1. ClusterRole에 wildcard(*) 권한이 없는지 확인
# 2. 4개 ServiceAccount 존재 여부 확인:
#    - sysdig-agent
#    - sysdig-admission-controller
#    - sysdig-node-analyzer
#    - sysdig-kspm-collector
```

#### 네트워크 정책 검증 (`test/validate-network-policies.sh`)

```bash
# 실행
bash test/validate-network-policies.sh

# 검증 항목:
# 1. default-deny-all 정책 존재 확인
# 2. 6개 컴포넌트별 정책 존재 확인:
#    - sysdig-agent-egress
#    - admission-controller-ingress
#    - admission-controller-egress
#    - node-analyzer-egress
#    - kspm-collector-egress
#    - dns-egress
```

### 5.6 환경별 테스트 체크리스트

#### Dev 환경

- [ ] ArgoCD 자동 동기화 동작 확인
- [ ] Agent DaemonSet이 모든 노드에 배포됨
- [ ] Agent 로그에 연결 성공 메시지 출력
- [ ] AC가 `dryRun` 모드로 동작 (차단 없이 로그만)
- [ ] PDB가 존재하지 않음 (dev overlay에서 제거)
- [ ] 리소스 제한이 축소된 값 적용됨

#### Staging 환경

- [ ] ArgoCD 자동 동기화 동작 확인
- [ ] 모든 컴포넌트 Running 상태
- [ ] AC가 `enforce` 모드로 동작 (failurePolicy=Ignore)
- [ ] `test/policy-violation.yaml` 배포 시 AC에서 차단
- [ ] `test/sample-deployment.yaml` 배포 정상 통과
- [ ] 모든 보안 기능 활성화 확인 (drift, malware, audit 등)

#### Production 환경

- [ ] ArgoCD **수동** 동기화만 가능 확인
- [ ] Custom Lua health check 동작 확인
- [ ] AC failurePolicy=**Fail** 적용 확인
- [ ] HPA가 동작 중 (3~8 replicas)
- [ ] PDB 적용 확인 (minAvailable: 1)
- [ ] `test/policy-violation.yaml` 배포 시 반드시 차단
- [ ] 연결 테스트 Job 성공
- [ ] RBAC/네트워크 정책 검증 스크립트 통과

---

## 부록 A: 주요 파일 경로 참조표

| 용도 | 파일 경로 |
|------|----------|
| ArgoCD App (Dev) | `argocd-apps/sysdig-shield-dev.yaml` |
| ArgoCD App (Staging) | `argocd-apps/sysdig-shield-staging.yaml` |
| ArgoCD App (Production) | `argocd-apps/sysdig-shield-production.yaml` |
| Helm Base Values | `helm-values/base-values.yaml` |
| Kustomize Base | `kustomize/base/kustomization.yaml` |
| Kustomize Dev Overlay | `kustomize/overlays/dev/kustomization.yaml` |
| Agent DaemonSet | `kustomize/base/sysdig-agent/daemonset.yaml` |
| Agent ConfigMap | `kustomize/base/sysdig-agent/configmap.yaml` |
| AC Deployment | `kustomize/base/admission-controller/deployment.yaml` |
| AC Webhook | `kustomize/base/admission-controller/validatingwebhookconfiguration.yaml` |
| Network Policies | `kustomize/base/network-policies/` |
| RBAC 리소스 | `kustomize/base/rbac/` |
| 시크릿 관리 가이드 | `secrets/README.md` |
| External Secrets 예제 | `secrets/external-secrets/` |
| 연결 테스트 | `test/connectivity-test.yaml` |
| 정책 위반 테스트 | `test/policy-violation.yaml` |
| RBAC 검증 스크립트 | `test/validate-rbac.sh` |
| 네트워크 정책 검증 | `test/validate-network-policies.sh` |
| 롤백 절차 | `test/rollback-test.md` |
| 설치 가이드 | `docs/installation.md` |
| 트러블슈팅 | `docs/troubleshooting.md` |
| 모니터링 | `docs/monitoring.md` |

---

## 부록 B: 트러블슈팅 요약

### Agent가 백엔드에 연결되지 않는 경우

```bash
# 1. Access Key 확인
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d

# 2. 네트워크 연결 확인
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- \
  curl -v https://collector.sysdigcloud.com:6443

# 3. Agent 로그 확인
kubectl logs daemonset/sysdig-agent -n sysdig-shield --tail=100

# 4. ConfigMap 확인
kubectl get configmap sysdig-agent -n sysdig-shield -o yaml
```

### Admission Controller가 배포를 차단하는 경우

```bash
# 1. AC 로그 확인
kubectl logs deployment/sysdig-admission-controller -n sysdig-shield

# 2. 긴급 우회: 웹훅 비활성화
kubectl delete validatingwebhookconfigurations sysdig-admission-controller

# 3. failurePolicy 확인
kubectl get validatingwebhookconfigurations sysdig-admission-controller -o yaml | grep failurePolicy
```

### ArgoCD 동기화 실패

```bash
# 1. ArgoCD 앱 상태 확인
argocd app get sysdig-shield-dev --show-events

# 2. 동기화 강제 실행
argocd app sync sysdig-shield-dev --force

# 3. 리소스 상태 확인
argocd app resources sysdig-shield-dev
```

### 리소스 부족으로 파드가 스케줄링되지 않는 경우

```bash
# 1. 이벤트 확인
kubectl get events -n sysdig-shield --sort-by='.lastTimestamp'

# 2. 노드 리소스 확인
kubectl describe nodes | grep -A5 "Allocated resources"

# 3. 리소스 requests 축소 (dev overlay 참조)
# kustomize/overlays/dev/sysdig-agent-resources-patch.yaml 참고
```
