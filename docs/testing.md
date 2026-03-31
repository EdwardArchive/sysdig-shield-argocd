# 테스트 및 검증 가이드

## 배포 전 검증

### 1. 매니페스트 Dry Run 검증

```bash
# 기본 매니페스트 검증
kubectl apply -f manifests/ --dry-run=server --recursive

# 환경별 Kustomize 오버레이 검증
kubectl kustomize kustomize/overlays/dev/ | kubectl apply --dry-run=server -f -
kubectl kustomize kustomize/overlays/staging/ | kubectl apply --dry-run=server -f -
kubectl kustomize kustomize/overlays/production/ | kubectl apply --dry-run=server -f -
```

### 2. Kustomize 오버레이 렌더링 확인

```bash
# 각 오버레이 렌더링 결과 확인
kubectl kustomize kustomize/overlays/dev/
kubectl kustomize kustomize/overlays/staging/
kubectl kustomize kustomize/overlays/production/
```

### 3. Helm Values 검증

```bash
# Helm 템플릿 렌더링 및 확인
helm template sysdig sysdig/shield \
  -f helm-values/base-values.yaml \
  -f helm-values/dev-values.yaml \
  --debug

# Kubernetes API 서버 검증
helm template sysdig sysdig/shield \
  -f helm-values/base-values.yaml \
  -f helm-values/production-values.yaml | kubectl apply --dry-run=server -f -
```

### 4. 시크릿 설정 검증

```bash
# 시크릿 존재 확인 (값은 출력하지 않음)
kubectl get secret sysdig-agent -n sysdig-shield
kubectl get secret sysdig-admission-controller-tls -n sysdig-shield

# 필수 키 존재 확인
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data}' | jq 'keys'
```

### 5. RBAC 검증

```bash
bash test/validate-rbac.sh
```

검증 항목:
- ClusterRole에 와일드카드(`*`) 권한이 없는지 확인
- 4개 ServiceAccount 존재 여부 (sysdig-agent, sysdig-admission-controller, sysdig-node-analyzer, sysdig-kspm-collector)

### 6. 네트워크 정책 검증

```bash
bash test/validate-network-policies.sh
```

검증 항목:
- `default-deny-all` 정책 존재
- 6개 컴포넌트별 정책 존재 (agent-egress, ac-ingress, ac-egress, na-egress, kspm-egress, dns-egress)

### 7. 백엔드 연결 테스트

```bash
# 연결 테스트 Job 실행
kubectl apply -f test/connectivity-test.yaml
kubectl wait --for=condition=complete job/sysdig-connectivity-test -n sysdig-shield --timeout=60s
kubectl logs -n sysdig-shield job/sysdig-connectivity-test

# 정리
kubectl delete -f test/connectivity-test.yaml
```

---

## 배포 후 검증

### 1. 전체 파드 상태 확인

```bash
# sysdig-shield 네임스페이스의 모든 파드 확인
kubectl get pods -n sysdig-shield

# 모든 파드가 Ready 상태가 될 때까지 대기
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/part-of=sysdig-shield \
  -n sysdig-shield \
  --timeout=300s
```

### 2. Agent 연결 확인

```bash
# 연결 성공 로그 확인
kubectl logs -n sysdig-shield daemonset/sysdig-agent --tail=50 | grep -E "connected|error|warn"

# Agent 상세 로그 확인
kubectl exec -n sysdig-shield daemonset/sysdig-agent -- cat /opt/draios/logs/draios.log | tail -20
```

### 3. Admission Controller 확인

```bash
# 웹훅 등록 확인
kubectl get validatingwebhookconfigurations | grep sysdig

# 정상 배포 테스트 (통과해야 함)
kubectl apply -f test/sample-deployment.yaml --dry-run=server

# 정책 위반 테스트 (운영 환경에서는 차단되어야 함)
kubectl apply -f test/policy-violation.yaml --dry-run=server

# AC 로그 확인
kubectl logs -n sysdig-shield deployment/sysdig-admission-controller --tail=50
```

### 4. Node Analyzer 확인

```bash
# 모든 노드에서 실행 중인지 확인
kubectl get pods -n sysdig-shield -l app.kubernetes.io/component=node-analyzer

# 스캔 로그 확인
kubectl logs -n sysdig-shield daemonset/sysdig-node-analyzer --tail=30
```

### 5. KSPM Collector 확인

```bash
# 파드 상태 확인
kubectl get pods -n sysdig-shield -l app.kubernetes.io/component=kspm-collector

# 포스처 데이터 수집 로그 확인
kubectl logs -n sysdig-shield deployment/sysdig-kspm-collector --tail=30
```

### 6. ArgoCD 동기화 상태

```bash
# 모든 Sysdig 애플리케이션 상태 확인
argocd app list | grep sysdig

# 상세 상태 확인
argocd app get sysdig-shield-production
```

---

## 환경별 검증

### 개발 환경

```bash
# AC가 dry-run 모드인지 확인
kubectl get configmap sysdig-admission-controller -n sysdig-shield -o yaml | grep dryRun

# 기능 제한 확인 (drift detection 등 비활성화)
kubectl get pods -n sysdig-shield
```

### 스테이징 환경

```bash
# AC 경고 모드 확인 (failurePolicy: Ignore)
kubectl apply -f test/policy-violation.yaml

# 모든 보안 기능 활성화 확인
kubectl logs -n sysdig-shield daemonset/sysdig-agent | grep -E "drift|malware|policy"
```

### 운영 환경

```bash
# AC 강제 모드 확인
kubectl get validatingwebhookconfiguration sysdig-admission-controller-webhook \
  -o jsonpath='{.webhooks[0].failurePolicy}'
# 예상 출력: Fail

# HPA 동작 확인
kubectl get hpa -n sysdig-shield

# PDB 적용 확인
kubectl get pdb -n sysdig-shield
```
