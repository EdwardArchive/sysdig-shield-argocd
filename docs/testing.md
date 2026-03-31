# 테스트 및 검증 가이드

## 배포 전 검증

### 1. Helm 템플릿 렌더링 검증

```bash
# Helm 저장소 추가
helm repo add sysdig https://charts.sysdig.com
helm repo update

# 개발 환경 렌더링 확인
helm template sysdig-shield sysdig/shield \
  --version 1.28.0 \
  -f helm-values/base-values.yaml \
  -f helm-values/dev-values.yaml \
  --namespace sysdig-shield \
  --debug

# Kubernetes API 서버 검증
helm template sysdig-shield sysdig/shield \
  --version 1.28.0 \
  -f helm-values/base-values.yaml \
  -f helm-values/production-values.yaml \
  --namespace sysdig-shield | kubectl apply --dry-run=server -f -
```

### 2. 시크릿 설정 검증

```bash
# 시크릿 존재 확인 (값은 출력하지 않음)
kubectl get secret sysdig-agent -n sysdig-shield
kubectl get secret sysdig-admission-controller-tls -n sysdig-shield

# 필수 키 존재 확인
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data}' | jq 'keys'
```

### 3. RBAC 검증

```bash
bash test/validate-rbac.sh
```

### 4. 네트워크 정책 검증

```bash
bash test/validate-network-policies.sh
```

### 5. 백엔드 연결 테스트

```bash
kubectl apply -f test/connectivity-test.yaml
kubectl wait --for=condition=complete job/sysdig-connectivity-test -n sysdig-shield --timeout=60s
kubectl logs -n sysdig-shield job/sysdig-connectivity-test
kubectl delete -f test/connectivity-test.yaml
```

---

## 배포 후 검증

### 1. 전체 파드 상태 확인

```bash
kubectl get pods -n sysdig-shield

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/part-of=sysdig-shield \
  -n sysdig-shield \
  --timeout=300s
```

### 2. Agent 연결 확인

```bash
kubectl logs -n sysdig-shield daemonset/sysdig-agent --tail=50 | grep -E "connected|error|warn"
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

### 4. ArgoCD 동기화 상태

```bash
argocd app list | grep sysdig
argocd app get sysdig-shield-production
```

### 5. Helm 릴리스 확인

```bash
# ArgoCD가 관리하는 Helm 릴리스 상태 확인
helm list -n sysdig-shield
```

---

## 환경별 검증

### 개발 환경

```bash
# AC가 dry-run 모드인지 확인 (values에서 dry_run: true)
# policy-violation.yaml 배포 시 차단 없이 로그만 기록
kubectl apply -f test/policy-violation.yaml --dry-run=server
```

### 스테이징 환경

```bash
# 모든 보안 기능 활성화 확인
kubectl logs -n sysdig-shield daemonset/sysdig-agent | grep -E "drift|malware|policy"
```

### 운영 환경

```bash
# AC failurePolicy=Fail 확인
kubectl get validatingwebhookconfiguration -o jsonpath='{.items[*].webhooks[*].failurePolicy}'

# HPA 동작 확인
kubectl get hpa -n sysdig-shield

# PDB 적용 확인
kubectl get pdb -n sysdig-shield
```
