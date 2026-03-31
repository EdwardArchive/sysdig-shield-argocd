# 보안 강화 체크리스트 및 인시던트 대응

## 운영 전 보안 검토

### RBAC
- [ ] ClusterRole에 와일드카드(`*`) 권한 없음
- [ ] ServiceAccount에 최소 권한 원칙 적용
- [ ] 정기 RBAC 감사 일정 수립

### 시크릿
- [ ] Git에 평문 시크릿 없음
- [ ] 시크릿 저장 시 암호화 (Encryption at rest)
- [ ] 시크릿 순환(Rotation) 활성화
- [ ] 접근 로깅 설정

### 네트워크 정책
- [ ] 기본 거부(Default Deny) 정책 활성화
- [ ] 컴포넌트별 정책 테스트 완료
- [ ] DNS Egress 정상 동작 확인
- [ ] 비인가 트래픽 차단 확인

### Admission Controller
- [ ] 감사 모드에서 정책 테스트 완료
- [ ] `failurePolicy` 적절 설정 (테스트 시 Ignore, 검증 후 Fail)
- [ ] 네임스페이스 제외 설정 완료
- [ ] 고가용성 구성 (3+ replicas)

### 파드 보안
- [ ] 가능한 경우 non-root 컨테이너 사용
- [ ] 리소스 제한(limits) 설정
- [ ] SecurityContext 설정
- [ ] Pod Security Standards 적용

### 규정 준수
- [ ] CIS Kubernetes Benchmark 통과 ([참조](https://www.cisecurity.org/benchmark/kubernetes))
- [ ] KSPM Collector 활성화
- [ ] 감사 로깅 활성화
- [ ] 규정 준수 보고서 검토

## 정기 보안 작업

| 주기 | 작업 |
|------|------|
| **주간** | Sysdig 알림 및 인시던트 검토 |
| **월간** | 컴포넌트 이미지 업데이트 |
| **분기** | RBAC 및 네트워크 정책 감사 |
| **연간** | 종합 보안 검토 |

---

## 인시던트 대응 절차

### 비상 연락처

- **플랫폼 팀**: (실제 연락처로 교체 필요)
- **보안 팀**: (실제 연락처로 교체 필요)
- **Sysdig 지원**: https://support.sysdig.com

### 인시던트 1: Admission Controller가 모든 배포를 차단

**심각도**: P1 — 운영 환경 영향

**즉시 조치**:
```bash
# 1. 긴급 우회 (웹훅 제거)
kubectl delete validatingwebhookconfiguration sysdig-admission-controller

# 2. 팀 알림

# 3. 원인 조사
kubectl logs -f deployment/sysdig-admission-controller -n sysdig-shield

# 4. 수정 후 재배포
argocd app sync sysdig-shield-production
```

### 인시던트 2: Agent 연결 장애

**심각도**: P2 — 모니터링 사각지대 발생

**조치**:
```bash
# 1. Agent 상태 확인
kubectl get pods -n sysdig-shield -l app.kubernetes.io/name=sysdig-agent

# 2. 로그 확인
kubectl logs daemonset/sysdig-agent -n sysdig-shield

# 3. 네트워크 연결 확인
kubectl exec -it daemonset/sysdig-agent -n sysdig-shield -- \
  curl -v https://app.sysdigcloud.com/api/ping

# 4. 시크릿 유효성 확인
kubectl get secret sysdig-agent -n sysdig-shield -o jsonpath='{.data.access-key}' | base64 -d
```

### 인시던트 3: 리소스 고갈

**심각도**: P2 — 성능 저하

**조치**:
```bash
# 1. 리소스 사용량 확인
kubectl top pods -n sysdig-shield
kubectl top nodes

# 2. 오버레이에서 리소스 제한 조정
# 3. 변경 사항 커밋 및 동기화
```

### AC 보안 침해 의심

```bash
# 긴급: 웹훅 삭제
kubectl delete validatingwebhookconfiguration sysdig-admission-controller

# 조사 후 재배포
argocd app sync sysdig-shield-production
```

### Agent 보안 침해 의심

```bash
# 격리: DaemonSet 삭제
kubectl delete daemonset sysdig-agent -n sysdig-shield

# 로그 조사 후 재배포
```

## 에스컬레이션 경로

| 단계 | 담당 | 시점 |
|------|------|------|
| L1 | 온콜 엔지니어 | 즉시 대응 |
| L2 | 플랫폼 팀 리드 | 30분 이내 미해결 시 |
| L3 | 보안 팀 | 보안 관련 중대 이슈 |
| L4 | Sysdig 지원 | 벤더 에스컬레이션 |

## 인시던트 사후 검토

P1/P2 인시던트 해결 후 반드시 수행:

1. 타임라인 및 조치 사항 문서화
2. 근본 원인 파악
3. 재발 방지 조치 적용
4. 런북 업데이트
5. 팀 회고 일정 수립
