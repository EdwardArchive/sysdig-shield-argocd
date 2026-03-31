# 롤백 검증 절차

Sysdig Shield 컴포넌트의 롤백 성공 여부를 검증하는 절차를 설명합니다.

## 롤백이 필요한 경우

- Admission Controller가 정상 워크로드를 예기치 않게 차단
- Agent로 인한 노드 불안정 (높은 CPU/메모리)
- 정책 변경으로 인한 과도한 오탐(False Positive)
- 업그레이드 실패로 컴포넌트가 비정상 상태

## 롤백 전 체크리스트

- [ ] 마지막으로 정상 동작한 Git 커밋 또는 Helm 차트 버전 확인
- [ ] 영향 받은 컴포넌트 파악 (Agent, AC, Node Analyzer, KSPM)
- [ ] 실패한 배포에서 시크릿 또는 CRD가 변경되었는지 확인
- [ ] 이해관계자에게 유지보수 기간 공지

## 롤백 절차

### 방법 1: ArgoCD 롤백 (GitOps)

```bash
# 마지막 성공 동기화 확인
argocd app history sysdig-shield-production

# 이전 리비전으로 롤백
argocd app rollback sysdig-shield-production <REVISION_ID>

# 롤백 상태 확인
argocd app get sysdig-shield-production
```

### 방법 2: Git Revert + ArgoCD 동기화

```bash
# 문제가 된 커밋을 되돌리기
git revert <COMMIT_SHA>
git push origin main

# ArgoCD 강제 동기화
argocd app sync sysdig-shield-production --force
```

### 방법 3: 긴급 Admission Controller 우회

AC가 중대한 인시던트 중 배포를 차단하는 경우:

```bash
# failurePolicy를 Ignore로 변경 (웹훅 실패 시에도 배포 허용)
kubectl patch validatingwebhookconfiguration sysdig-admission-controller-webhook \
  --type='json' \
  -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Ignore"}]'

# 또는 웹훅 일시 비활성화
kubectl delete validatingwebhookconfiguration sysdig-admission-controller-webhook

# 인시던트 해결 후 복구
kubectl apply -f manifests/admission-controller/validatingwebhookconfiguration.yaml
```

### 방법 4: Helm 롤백

```bash
# Helm 릴리스 목록 확인
helm list -n sysdig-shield

# 롤백 히스토리 확인
helm history sysdig -n sysdig-shield

# 이전 릴리스로 롤백
helm rollback sysdig <REVISION> -n sysdig-shield

# 롤백 확인
helm status sysdig -n sysdig-shield
```

## 롤백 후 검증

### 1. 컴포넌트 상태 확인

```bash
# 모든 파드가 Running 상태인지 확인
kubectl get pods -n sysdig-shield
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=sysdig-shield \
  -n sysdig-shield --timeout=300s
```

### 2. Agent 연결 확인

```bash
kubectl logs -n sysdig-shield daemonset/sysdig-agent --tail=30 | grep -E "connected|error"
```

### 3. Admission Controller 확인

```bash
# 웹훅이 정상 동작하는지 확인
kubectl apply -f test/sample-deployment.yaml --dry-run=server

# 정책이 올바르게 적용되는지 확인
kubectl get validatingwebhookconfiguration sysdig-admission-controller-webhook \
  -o jsonpath='{.webhooks[0].failurePolicy}'
```

### 4. 데이터 손실 확인

```bash
# Sysdig UI에서 확인:
# - Integrations > Agents: Agent 보고 상태
# - Security > Compliance: 포스처 데이터
# - Events > Activity Audit: 최근 이벤트
```

### 5. 연결 테스트 실행

```bash
kubectl apply -f test/connectivity-test.yaml
kubectl wait --for=condition=complete job/sysdig-connectivity-test -n sysdig-shield --timeout=60s
kubectl logs -n sysdig-shield job/sysdig-connectivity-test
kubectl delete -f test/connectivity-test.yaml
```

## 롤백 검증 완료 체크리스트

인시던트 종료 전 아래 항목을 모두 확인합니다:

- [ ] 모든 Sysdig 파드 Running 및 Ready 상태
- [ ] Agent가 Sysdig 백엔드에 연결됨 (UI에서 확인)
- [ ] Admission Controller가 정상 워크로드를 허용
- [ ] 테스트 배포 통과 (`test/sample-deployment.yaml`)
- [ ] 연결 테스트 통과
- [ ] 인시던트 런북에 문서화 완료
- [ ] 필요 시 사후 검토(Post-mortem) 일정 수립
