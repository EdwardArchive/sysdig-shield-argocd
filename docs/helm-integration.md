# Helm 차트 통합 가이드

Kustomize 기반 배포의 대안으로 공식 Sysdig Helm 차트를 사용하는 방법을 설명합니다.

## 개요

이 저장소는 Kustomize를 주요 배포 방식으로 사용하지만, 공식 Sysdig Helm 차트와 환경별 values 파일을 활용한 배포도 지원합니다.

## Helm 차트 정보

- **차트 저장소**: https://charts.sysdig.com
- **차트 이름**: `sysdig/shield`
- **권장 버전**: 특정 버전 고정 (예: 1.28.0)
- **설정 구조**: `features` 키 기반 기능별 설정

> **출처**: [Sysdig Helm Charts GitHub](https://github.com/sysdiglabs/charts)

## 설정

### 1. Sysdig Helm 저장소 추가

```bash
helm repo add sysdig https://charts.sysdig.com
helm repo update
```

### 2. 환경별 설치

#### 개발 환경
```bash
helm install sysdig-shield sysdig/shield \
  --namespace sysdig-shield \
  --create-namespace \
  --version 1.28.0 \
  --values helm-values/base-values.yaml \
  --values helm-values/dev-values.yaml
```

#### 스테이징 환경
```bash
helm install sysdig-shield sysdig/shield \
  --namespace sysdig-shield \
  --create-namespace \
  --version 1.28.0 \
  --values helm-values/base-values.yaml \
  --values helm-values/staging-values.yaml
```

#### 운영 환경
```bash
helm install sysdig-shield sysdig/shield \
  --namespace sysdig-shield \
  --create-namespace \
  --version 1.28.0 \
  --values helm-values/base-values.yaml \
  --values helm-values/production-values.yaml
```

## 기능별 설정 구조

### 기본 클러스터 설정
```yaml
cluster_config:
  name: "cluster-name"

sysdig_endpoint:
  region: us1  # us1, us2, us3, us4, eu1, au1, me2
  access_key_existing_secret: sysdig-agent
```

### 주요 기능

- **admission_control**: 배포 시점 정책 검증
  - `failure_policy`: Fail (차단) 또는 Ignore (감사)
  - `dry_run`: 정책 테스트 (적용 없이 로깅만)
  - `container_vulnerability_management`: 취약 이미지 차단
  - `posture`: 포스처 규정 준수 검증

- **posture**: 보안 태세 평가
  - `cluster_posture`: Kubernetes 구성 스캔
  - `host_posture`: 호스트 OS 규정 준수 검사

- **vulnerability_management**: CVE 탐지
  - `container_vulnerability_management`: 컨테이너 이미지 스캔
  - `host_vulnerability_management`: 호스트 OS 취약점 스캔
  - `in_use`: 실제 사용 중인 패키지만 추적

- **detections**: 런타임 위협 탐지
  - `drift_control`: 실행 파일 변경 감지
  - `malware_control`: 악성코드 탐지
  - `ml_policies`: ML 기반 이상 행위 탐지
  - `kubernetes_audit`: 감사 로그 분석
  - `file_integrity_monitoring`: 파일 변경 추적

- **investigations**: 포렌식 및 조사
  - `activity_audit`: 시스템 콜 감사
  - `network_security`: 네트워크 트래픽 모니터링
  - `captures`: 패킷 캡처

- **respond**: 자동 대응
  - `rapid_response`: 인터랙티브 셸 접근

> **출처**: [Sysdig Shield Helm Chart 문서](https://docs.sysdig.com/en/docs/installation/sysdig-secure/install-agent-components/kubernetes/#install-using-helm)

## 하이브리드 방식: Helm + Kustomize

Helm 템플릿과 Kustomize 패치를 결합할 수 있습니다:

```bash
# Helm 차트를 YAML로 렌더링 후 Kustomize 적용
helm template sysdig-shield sysdig/shield \
  --version 1.28.0 \
  --values helm-values/base-values.yaml \
  --namespace sysdig-shield | kubectl kustomize kustomize/overlays/production/
```

## 비교: Helm vs Kustomize

| 항목 | Helm | Kustomize |
|------|------|-----------|
| **장점** | 공식 차트 업데이트, 간편한 업그레이드 | 세밀한 제어, 커스텀 패치 |
| **적합** | 표준 배포, 빠른 시작 | 고급 설정, 환경별 세밀 조정 |
| **조합** | 하이브리드 방식으로 양쪽 장점 활용 가능 | |
