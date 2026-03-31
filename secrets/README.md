# Sysdig Shield 시크릿 관리

이 디렉토리는 Sysdig Shield 배포를 위한 시크릿 관리 예제와 설정을 포함합니다. **중요**: 평문 시크릿은 절대 Git에 커밋하지 마세요.

## 3가지 지원 방식

### 1. External Secrets Operator (권장)

**적합 대상**: 기존 시크릿 저장소를 보유한 조직 (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager, Azure Key Vault)

**장점**:
- 기존 시크릿 인프라와 연동
- 자동 시크릿 순환 지원
- 중앙 집중 시크릿 관리
- Git 저장소에 시크릿 없음

**설정**:
1. 클러스터에 External Secrets Operator 설치
2. SecretStore 또는 ClusterSecretStore 생성 (`external-secrets/secret-store.yaml` 참조)
3. ExternalSecret 리소스 생성 (`external-secrets/external-secret-sysdig-agent.yaml` 참조)
4. Operator가 외부 저장소에서 Kubernetes Secret으로 자동 동기화

**필수 시크릿**:
- `sysdig-agent`: Sysdig Access Key
- `sysdig-admission-controller-tls`: 웹훅용 TLS 인증서 및 키

> **출처**: [External Secrets Operator 공식 문서](https://external-secrets.io/)

---

### 2. Sealed Secrets

**적합 대상**: 외부 시크릿 인프라가 없는 소규모 배포

**장점**:
- 암호화된 시크릿을 Git에 커밋 가능
- sealed-secrets 컨트롤러 외 외부 의존성 없음
- GitOps 친화적

**설정**:
1. 클러스터에 sealed-secrets 컨트롤러 설치
2. `kubeseal` CLI로 시크릿 암호화
3. SealedSecret 리소스를 Git에 커밋 (`sealed-secrets/sealed-secret-example.yaml` 참조)
4. 컨트롤러가 복호화 후 Kubernetes Secret 생성

**예시**:
```bash
# 시크릿 생성 및 봉인(Seal)
kubectl create secret generic sysdig-agent \
  --from-literal=access-key=YOUR_SYSDIG_ACCESS_KEY \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secrets/sysdig-agent-sealed.yaml

# 봉인된 시크릿을 Git에 커밋
git add sealed-secrets/sysdig-agent-sealed.yaml
git commit -m "Sysdig Access Key Sealed Secret 추가"
```

> **출처**: [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)

---

### 3. ArgoCD Vault Plugin

**적합 대상**: ArgoCD와 함께 HashiCorp Vault를 사용하는 조직

**장점**:
- 배포 시점에 시크릿 주입
- ArgoCD에 시크릿 저장되지 않음
- 기존 Vault 인프라 활용

**설정**:
1. ArgoCD에 Vault 플러그인 설정
2. 매니페스트에 플레이스홀더 사용 (`argocd-vault-plugin/secret-with-placeholders.yaml` 참조)
3. ArgoCD 동기화 시 Vault에서 실제 값으로 대체

**플레이스홀더 예시**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sysdig-agent
data:
  access-key: <path:secret/data/sysdig#access-key | base64encode>
```

> **출처**: [ArgoCD Vault Plugin 문서](https://argocd-vault-plugin.readthedocs.io/)

---

## 시크릿 검증

배포 전 시크릿을 검증합니다:

### 1. Access Key 형식 확인
```bash
# Access Key는 UUID 또는 유효한 API 키여야 함
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d
```

### 2. 백엔드 연결 테스트
```bash
# Sysdig 백엔드 연결 테스트
curl -H "Authorization: Bearer $(kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d)" \
  https://app.sysdigcloud.com/api/ping
```

예상 응답: `{"status":"ok"}`

### 3. TLS 인증서 확인
```bash
# AC 인증서 유효 기간 확인
kubectl get secret sysdig-admission-controller-tls -n sysdig-shield -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# 인증서 DNS 이름 확인
kubectl get secret sysdig-admission-controller-tls -n sysdig-shield -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -text | grep DNS
```

예상 DNS: `sysdig-admission-controller.sysdig-shield.svc`

### 4. 배포 전 체크리스트
- [ ] 외부 시크릿 저장소에 Access Key 생성 또는 Sealed Secret 생성
- [ ] Sysdig 백엔드에 Access Key 연결 테스트 완료
- [ ] AC용 TLS 인증서 생성 완료
- [ ] 인증서 유효 기간 최소 90일 이상
- [ ] 인증서 DNS 이름이 서비스와 일치: `sysdig-admission-controller.sysdig-shield.svc`
- [ ] Git 저장소에 평문 시크릿 없음
- [ ] 시크릿 순환 일정 문서화

---

## 문제 해결

### External Secrets 동기화 안 됨
```bash
# ExternalSecret 상태 확인
kubectl describe externalsecret sysdig-agent -n sysdig-shield

# SecretStore 연결 확인
kubectl describe secretstore aws-secrets-manager -n sysdig-shield

# External Secrets Operator 로그 확인
kubectl logs -n external-secrets-system deployment/external-secrets
```

### Sealed Secrets 복호화 안 됨
```bash
# sealed-secrets 컨트롤러 실행 확인
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# 컨트롤러 로그 확인
kubectl logs -n kube-system -l name=sealed-secrets-controller

# SealedSecret 생성 확인
kubectl get sealedsecrets -n sysdig-shield
```

### Vault Plugin 문제
```bash
# ArgoCD 애플리케이션 이벤트 확인
argocd app get sysdig-shield --show-events

# Vault 인증 확인
kubectl exec -it -n argocd deployment/argocd-repo-server -- vault status

# Vault 경로 접근 테스트
vault kv get secret/sysdig
```

---

## 보안 모범 사례

1. **평문 시크릿 커밋 금지**: .gitignore로 secrets/ 디렉토리 제외
2. **정기적 시크릿 순환**: 자동 순환 설정 (최소 분기별)
3. **최소 권한 사용**: 시크릿 저장소에 최소 IAM/RBAC 권한 부여
4. **시크릿 접근 감사**: Vault/AWS Secrets Manager에서 감사 로깅 활성화
5. **저장 시 암호화**: Kubernetes Secrets에 EncryptionConfiguration 적용
6. **유출 감시**: 시크릿 스캔 도구 활용 (GitGuardian, TruffleHog)

---

## 빠른 참조

| 시크릿 이름 | 용도 | 필수 | 형식 |
|-------------|------|------|------|
| `sysdig-agent` | Sysdig 백엔드 인증 | 예 | `access-key`: UUID/API 키 |
| `sysdig-admission-controller-tls` | 웹훅 TLS | 예 | `tls.crt`, `tls.key` |

## 참고 자료

- [External Secrets Operator 공식 문서](https://external-secrets.io/)
- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/)
- [Sysdig Secure 공식 문서](https://docs.sysdig.com/en/sysdig-secure.html)
