# 모니터링 가이드

## 개요

Sysdig Shield 컴포넌트의 상태를 Prometheus/Grafana를 통해 모니터링하고, 주요 장애 시나리오에 대한 알림을 설정하는 방법을 설명합니다.

## Prometheus 모니터링

### 메트릭 엔드포인트

| 컴포넌트 | 포트 | 경로 |
|----------|------|------|
| sysdig-agent | 24231 | /metrics |
| admission-controller | 8080 | /metrics |
| node-analyzer | 8080 | /metrics |
| kspm-collector | 8080 | /metrics |

### ServiceMonitor 설정

Prometheus Operator를 사용하는 경우 ServiceMonitor를 생성합니다:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sysdig-shield
  namespace: sysdig-shield
  labels:
    app.kubernetes.io/part-of: sysdig-shield
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: sysdig-shield
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

> **출처**: [Prometheus Operator - ServiceMonitor](https://prometheus-operator.dev/docs/user-guides/getting-started/)

### 주요 모니터링 메트릭

**Agent 메트릭:**
- `sysdig_agent_connected` — 백엔드 연결 상태 (1=연결, 0=단절)
- `sysdig_agent_events_total` — 생성된 보안 이벤트 총 수
- `sysdig_agent_cpu_usage_ratio` — Agent CPU 사용률 (0.8 초과 시 알림)
- `sysdig_agent_memory_bytes` — Agent 메모리 사용량

**Admission Controller 메트릭:**
- `admission_controller_requests_total` — 웹훅 요청 총 수
- `admission_controller_requests_denied_total` — 거부된 요청 (정책 위반)
- `admission_controller_request_duration_seconds` — 요청 지연 시간
- `admission_controller_errors_total` — 내부 오류 수

**Node Analyzer 메트릭:**
- `node_analyzer_scans_total` — 완료된 이미지 스캔 수
- `node_analyzer_scan_errors_total` — 실패한 스캔 수
- `node_analyzer_queue_depth` — 스캔 대기열 깊이

## 알림 설정

### 주요 알림 규칙

```yaml
groups:
- name: sysdig-shield-critical
  rules:

  # Agent 백엔드 연결 끊김
  - alert: SysdigAgentDisconnected
    expr: sysdig_agent_connected == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Sysdig Agent 연결 끊김: {{ $labels.node }}"
      description: "5분 이상 Agent 연결이 끊긴 상태. 보안 모니터링에 영향."
      runbook: "docs/troubleshooting.md"

  # Admission Controller 미응답
  - alert: SysdigAdmissionControllerDown
    expr: up{job="sysdig-admission-controller"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Sysdig Admission Controller 다운"
      description: "AC 파드가 응답하지 않음. 정책 적용에 영향."

  # AC 높은 오류율
  - alert: SysdigAdmissionControllerErrors
    expr: rate(admission_controller_errors_total[5m]) > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Sysdig AC 높은 오류율"
      description: "5분간 오류율이 10%를 초과."

  # 웹훅 높은 지연 시간
  - alert: SysdigWebhookHighLatency
    expr: histogram_quantile(0.99, rate(admission_controller_request_duration_seconds_bucket[5m])) > 5
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Sysdig 웹훅 높은 지연 시간"
      description: "P99 웹훅 지연이 5초를 초과. 배포 타임아웃 가능."

  # 파드 Crash Looping
  - alert: SysdigPodCrashLooping
    expr: |
      increase(kube_pod_container_status_restarts_total{
        namespace="sysdig-shield"
      }[1h]) > 3
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Sysdig 파드 크래시 루프: {{ $labels.pod }}"
      description: "파드 {{ $labels.pod }}이(가) 1시간 내 3회 이상 재시작."

  # Agent 높은 CPU 사용
  - alert: SysdigAgentHighCPU
    expr: sysdig_agent_cpu_usage_ratio > 0.85
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Sysdig Agent 높은 CPU: {{ $labels.node }}"
      description: "Agent CPU 사용률이 10분간 85%를 초과. 리소스 제한 조정 검토."
```

### PrometheusRule 적용

```bash
# Prometheus Operator를 사용하는 경우 PrometheusRule로 적용
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sysdig-shield-alerts
  namespace: sysdig-shield
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    # 위의 알림 규칙 그룹을 여기에 삽입
EOF
```

## Grafana 대시보드

### 사전 구성 대시보드 가져오기

Sysdig는 공식 Grafana 대시보드를 제공합니다:

```bash
# Grafana API를 통해 가져오기
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"dashboard": {"id": null, "uid": null}, "folderId": 0, "overwrite": false}' \
  http://admin:password@grafana:3000/api/dashboards/import
```

> **출처**: [Grafana 대시보드 가져오기](https://grafana.com/docs/grafana/latest/dashboards/manage-dashboards/)

### 주요 대시보드 패널

1. **Agent 상태** — 노드별 연결/단절 Agent 현황
2. **이벤트 발생률** — 분당 보안 이벤트 발생 수
3. **어드미션 결정** — 허용/거부/오류 비율 추이
4. **웹훅 지연 시간** — P50/P95/P99 요청 처리 시간
5. **컴포넌트 가동률** — 컴포넌트별 가용성

## 헬스 체크

### Readiness/Liveness 프로브 확인

```bash
kubectl describe pods -n sysdig-shield | grep -A5 "Liveness\|Readiness"
```

### ArgoCD 헬스 연동

ArgoCD 애플리케이션에는 커스텀 헬스 체크가 설정되어 있습니다 (운영 환경의 경우 Lua 스크립트를 사용). 자세한 내용은 [`argocd-apps/sysdig-shield-production.yaml`](../argocd-apps/sysdig-shield-production.yaml)을 참조하세요.

```bash
argocd app list | grep sysdig
```

## 온콜 빠른 참조

- 알림 대응 절차: [security.md](security.md) (인시던트 대응 섹션)
- 컴포넌트별 문제 해결: [troubleshooting.md](troubleshooting.md)
