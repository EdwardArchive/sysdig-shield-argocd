# 유지보수, 업그레이드 및 재해 복구 가이드

## 정기 유지보수 작업

### 분기별 검토
- **RBAC 감사**: 미사용 권한 검토 및 제거
- **시크릿 순환**: Sysdig Access Key 교체
- **네트워크 정책 검토**: 정책의 적절성 확인

### 월간 작업
- Sysdig 컴포넌트 이미지를 최신 버전으로 업데이트
- Admission Controller 정책 검토
- 리소스 사용량 확인 및 제한 조정

## 업그레이드 절차

### 1. 매니페스트 업데이트

```bash
# 이미지 태그 또는 설정 업데이트 후 커밋
git commit -am "Sysdig 컴포넌트를 vX.Y.Z로 업데이트"
git push
```

### 2. 변경 사항 동기화

```bash
# 개발 환경 (자동 동기화 — 자동 적용됨)
# 수동으로 확인하려면:
argocd app sync sysdig-shield-dev

# 운영 환경 (수동 동기화)
argocd app sync sysdig-shield-production
```

### 3. 업그레이드 확인

```bash
kubectl rollout status daemonset/sysdig-agent -n sysdig-shield
kubectl rollout status deployment/sysdig-admission-controller -n sysdig-shield
```

### 롤백

```bash
# 히스토리 확인
argocd app history sysdig-shield-production

# 특정 리비전으로 롤백
argocd app rollback sysdig-shield-production <REVISION>
```

상세 롤백 절차 및 검증 방법은 [`test/rollback-test.md`](../test/rollback-test.md)를 참조하세요.

## 시크릿 순환

### Sysdig Access Key 교체

```bash
# 1. Sysdig 포털에서 새 키 생성
# 2. 외부 시크릿 저장소 업데이트 또는 새로운 Sealed Secret 생성
# 3. 컴포넌트 재시작
kubectl rollout restart daemonset/sysdig-agent -n sysdig-shield
```

### TLS 인증서 순환

cert-manager가 자동으로 인증서를 갱신합니다. 상태 확인:

```bash
kubectl get certificate -n sysdig-shield
```

## 백업 및 재해 복구

### 백업 대상

Sysdig Shield는 완전히 선언적이며, 모든 설정은 이 Git 저장소에 저장됩니다. Git 자체가 주요 백업입니다.

#### 추가 백업 항목

| 항목 | 위치 | 백업 방법 |
|------|------|-----------|
| Git 저장소 | GitHub/GitLab | 자동 미러링 또는 주기적 복제 |
| Sysdig Access Key | AWS Secrets Manager / Vault | 제공업체 관리 백업 |
| TLS 인증서 | K8s Secrets / cert-manager | 클러스터 etcd 백업에 포함 |
| ArgoCD 앱 상태 | ArgoCD | ArgoCD 네임스페이스 백업 또는 `argocd export` |

### 백업 절차

#### 저장소 백업

```bash
# 보조 리모트로 미러링
git remote add backup git@backup-host:org/sysdig-shield-argocd.git
git push backup --mirror

# 로컬 백업 번들 생성
git bundle create sysdig-shield-argocd-$(date +%Y%m%d).bundle --all
```

#### ArgoCD 상태 내보내기

```bash
# 모든 ArgoCD Application 정의 내보내기
argocd app list -o yaml > argocd-apps-backup-$(date +%Y%m%d).yaml

# ArgoCD 프로젝트 정의 내보내기
argocd proj list -o yaml > argocd-projects-backup-$(date +%Y%m%d).yaml
```

#### Kubernetes 시크릿 백업

```bash
# 시크릿 내보내기 (암호화하여 저장, 절대 평문으로 Git에 커밋하지 않음)
kubectl get secrets -n sysdig-shield -o yaml | \
  kubeseal --format yaml > sealed-secrets-backup-$(date +%Y%m%d).yaml
```

### 재해 복구

#### Git에서 전체 클러스터 복구

클러스터를 잃은 경우 Git에서 재배포합니다:

```bash
# 1. ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. 외부 시크릿 저장소에서 시크릿 복원
kubectl apply -f secrets/external-secrets/

# 3. ArgoCD 애플리케이션 적용
kubectl apply -f argocd-apps/

# 4. 동기화 대기
argocd app wait sysdig-shield-production --health --timeout 600
```

#### 복구 시간 목표

| 시나리오 | RTO | RPO |
|----------|-----|-----|
| 파드 장애 | < 2분 (자동 복구) | 0 |
| 노드 장애 | < 5분 (재스케줄링) | 0 |
| 클러스터 재구축 | < 30분 | 0 (설정은 Git에 보존) |
| 리전 장애 | < 60분 | 0 (설정은 Git에 보존) |

## 온콜 절차

### 온콜 엔지니어 책임

- SLA 내 Sysdig 컴포넌트 알림 대응
- 필요 시 긴급 Admission Controller 우회 수행
- 제품 버그에 대한 벤더 지원 에스컬레이션

### 알림 대응 SLA

| 심각도 | 대응 시간 | 해결 시간 |
|--------|----------|-----------|
| Critical (Agent 다운, AC 다운) | 15분 | 1시간 |
| Warning (높은 지연, 높은 CPU) | 1시간 | 4시간 |
| Info | 다음 영업일 | 다음 스프린트 |

### 에스컬레이션 경로

1. **온콜 엔지니어** — 1차 대응, 초기 분류
2. **플랫폼 팀 리드** — SLA 내 미해결 또는 클러스터 전체 변경 필요 시
3. **Sysdig 지원** — 제품 버그: [support.sysdig.com](https://support.sysdig.com)

### Sysdig 지원 정보

```bash
# Sysdig 지원팀을 위한 진단 번들 수집
kubectl exec -n sysdig-shield daemonset/sysdig-agent -- \
  /opt/draios/bin/sysdig-agent-check --bundle

# Agent 버전 확인
kubectl exec -n sysdig-shield daemonset/sysdig-agent -- \
  cat /opt/draios/version/sysdig-agent
```

### 주요 런북 참조

| 시나리오 | 런북 |
|----------|------|
| Agent 연결 끊김 | [troubleshooting.md](troubleshooting.md) |
| AC 배포 차단 | [troubleshooting.md](troubleshooting.md) |
| 긴급 AC 우회 | [security.md](security.md) (인시던트 대응 섹션) |
| 롤백 필요 | [test/rollback-test.md](../test/rollback-test.md) |
