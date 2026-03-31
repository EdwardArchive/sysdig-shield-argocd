# 문제 해결 가이드

## 일반적인 문제

### Sysdig Agent 연결 불가

**증상**: Agent 파드가 실행 중이나 Sysdig 백엔드에 데이터를 전송하지 않음

**진단**:
```bash
# Agent 로그 확인
kubectl logs -f daemonset/sysdig-agent -n sysdig-shield

# Access Key 확인
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d

# 연결 테스트
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- curl -v https://app.sysdigcloud.com/api/ping
```

**해결 방법**:
- Access Key가 올바른지 확인
- 네트워크 정책이 Sysdig 백엔드로의 Egress를 허용하는지 확인
- 방화벽이 HTTPS 트래픽(app.sysdigcloud.com)을 허용하는지 확인
- 리전별 Collector URL이 올바른지 확인 ([설치 가이드](installation.md) 리전 표 참조)

### Admission Controller가 모든 배포를 차단

**증상**: 모든 파드 생성이 웹훅 타임아웃 또는 거부로 실패

**긴급 우회**:
```bash
# 웹훅 설정 삭제 (긴급 상황에서만)
kubectl delete validatingwebhookconfiguration sysdig-admission-controller

# 수정 후 재배포
argocd app sync sysdig-shield-production
```

**근본 원인 확인**:
- AC 파드가 Ready 상태가 아님
- TLS 인증서 문제
- 네트워크 정책이 API 서버 통신을 차단

**해결 방법**:
```bash
# AC 상태 확인
kubectl get pods -n sysdig-shield -l app.kubernetes.io/name=sysdig-admission-controller

# 웹훅 설정 확인
kubectl describe validatingwebhookconfiguration sysdig-admission-controller

# TLS 인증서 확인
kubectl get secret sysdig-admission-controller-tls -n sysdig-shield
```

### 네트워크 연결 문제

**증상**: 파드가 Sysdig 백엔드 또는 다른 파드에 연결할 수 없음

**진단**:
```bash
# DNS 확인
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup app.sysdigcloud.com

# 연결 테스트
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -v https://app.sysdigcloud.com
```

**해결 방법**:
- 네트워크 정책 검토 (`kustomize/base/network-policies/`)
- DNS Egress 허용 여부 확인 (`dns-egress.yaml`)
- 방화벽 규칙 확인

### ArgoCD 동기화 실패

**증상**: ArgoCD에서 "OutOfSync" 표시 또는 동기화 실패

**진단**:
```bash
argocd app get sysdig-shield-production --show-events
argocd app diff sysdig-shield-production
```

**해결 방법**:
```bash
# 강제 동기화 (prune 포함)
argocd app sync sysdig-shield-production --force --prune

# 하드 리프레시
argocd app sync sysdig-shield-production --force --replace
```

## 성능 문제

### 높은 리소스 사용

```bash
kubectl top pods -n sysdig-shield
kubectl top nodes
```

환경별 오버레이에서 리소스 제한을 조정합니다. 상세 설정은 [설치 가이드](installation.md)의 리소스 제한 표를 참조하세요.

### 이미지 스캔 지연

Node Analyzer ConfigMap에서 스캔 캐싱 및 속도 제한을 설정합니다.

## 지원

- **Sysdig 지원 포털**: https://support.sysdig.com
- **Sysdig 공식 문서**: https://docs.sysdig.com
- **ArgoCD 공식 문서**: https://argo-cd.readthedocs.io/
