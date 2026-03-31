#!/bin/bash
# ============================================================
# Sysdig Shield ArgoCD 배포 테스트 스크립트 (minikube)
#
# ArgoCD가 Helm 차트를 렌더링하여 배포합니다.
# 로컬에 Helm CLI가 필요하지 않습니다.
#
# 사전 요구사항:
#   - minikube (실행 중)
#   - kubectl
#
# 사용법:
#   1. 환경 변수 설정 (아래 참조)
#   2. bash test/minikube-test-deploy.sh
#
# 정리:
#   bash test/minikube-test-deploy.sh cleanup
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/minikube-test-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# ============================================================
# [필수] 환경 변수 설정
#
# export SYSDIG_ACCESS_KEY="your-access-key"
# export SYSDIG_API_TOKEN="your-api-token"
# export SYSDIG_API_URL="https://sysdig.yourcompany.com"
# export SYSDIG_COLLECTOR_HOST="sysdig.yourcompany.com"
# ============================================================
SYSDIG_ACCESS_KEY="${SYSDIG_ACCESS_KEY:-<YOUR_ACCESS_KEY>}"
SYSDIG_API_TOKEN="${SYSDIG_API_TOKEN:-<YOUR_API_TOKEN>}"
SYSDIG_API_URL="${SYSDIG_API_URL:-https://<YOUR_SYSDIG_DOMAIN>}"
SYSDIG_COLLECTOR_HOST="${SYSDIG_COLLECTOR_HOST:-<YOUR_SYSDIG_DOMAIN>}"
SYSDIG_COLLECTOR_PORT="${SYSDIG_COLLECTOR_PORT:-6443}"

ARGOCD_NS="argocd"
SYSDIG_NS="sysdig-shield"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

error() {
    log "[ERROR] $1"
    exit 1
}

# ============================================================
# 정리 함수
# ============================================================
cleanup() {
    log "=== 정리 시작 ==="

    log "ArgoCD Application 삭제..."
    kubectl delete application sysdig-shield-test -n "$ARGOCD_NS" --ignore-not-found 2>/dev/null || true

    log "Sysdig 네임스페이스 삭제 (ArgoCD가 관리하던 리소스 포함)..."
    kubectl delete namespace "$SYSDIG_NS" --ignore-not-found 2>/dev/null || true

    log "ArgoCD 삭제..."
    kubectl delete namespace "$ARGOCD_NS" --ignore-not-found 2>/dev/null || true

    log "=== 정리 완료 ==="
}

if [[ "${1:-}" == "cleanup" ]]; then
    cleanup
    exit 0
fi

log "=== Sysdig Shield ArgoCD 배포 테스트 시작 ==="
log "로그 파일: $LOG_FILE"

# ============================================================
# Step 0: 사전 검증
# ============================================================
log "--- Step 0: 사전 검증 ---"

minikube status >/dev/null 2>&1 || error "minikube가 실행 중이지 않습니다. 'minikube start'를 먼저 실행하세요."
log "minikube: 실행 중"

kubectl cluster-info >/dev/null 2>&1 || error "kubectl이 클러스터에 연결할 수 없습니다."
log "kubectl: 클러스터 연결 확인"

# ============================================================
# Step 1: ArgoCD 설치
# ============================================================
log "--- Step 1: ArgoCD 설치 ---"

if kubectl get namespace "$ARGOCD_NS" &>/dev/null; then
    log "ArgoCD 네임스페이스가 이미 존재합니다. 건너뜁니다."
else
    log "ArgoCD 설치 중..."
    kubectl create namespace "$ARGOCD_NS" 2>&1 | tee -a "$LOG_FILE"
    kubectl apply -n "$ARGOCD_NS" \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>&1 | tee -a "$LOG_FILE" || true

    log "ArgoCD 파드 준비 대기 (최대 5분)..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n "$ARGOCD_NS" --timeout=300s 2>&1 | tee -a "$LOG_FILE"
    log "ArgoCD 설치 완료"
fi

ARGOCD_INITIAL_PW=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "(이미 삭제됨)")
log "ArgoCD 초기 비밀번호: $ARGOCD_INITIAL_PW"

# ============================================================
# Step 2: Sysdig 네임스페이스 및 시크릿 생성
#
# 시크릿은 ArgoCD가 관리하지 않습니다.
# 클러스터에 미리 생성해두어야 합니다.
# ============================================================
log "--- Step 2: Sysdig 네임스페이스 및 시크릿 생성 ---"

kubectl create namespace "$SYSDIG_NS" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"

kubectl create secret generic sysdig-agent \
    --from-literal=access-key="$SYSDIG_ACCESS_KEY" \
    -n "$SYSDIG_NS" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"

log "시크릿 생성 완료"

# ============================================================
# Step 3: ArgoCD Application 생성 (Helm 차트를 ArgoCD가 배포)
#
# 핵심: ArgoCD 서버가 내장된 Helm으로 차트를 렌더링합니다.
#        로컬이나 대상 클러스터에 Helm CLI가 필요 없습니다.
#
# source.helm.valuesObject로 values를 인라인 전달합니다.
# (Git 저장소를 등록하지 않고도 테스트 가능)
# ============================================================
log "--- Step 3: ArgoCD Application 생성 ---"

cat <<EOF | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sysdig-shield-test
  namespace: ${ARGOCD_NS}
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  # ArgoCD가 Helm 차트를 직접 가져와서 렌더링합니다
  source:
    repoURL: https://charts.sysdig.com
    chart: shield
    targetRevision: "1.28.0"
    helm:
      valuesObject:
        cluster_config:
          name: "minikube-test"
          tags:
            environment: test

        sysdig_endpoint:
          region: custom
          access_key: "${SYSDIG_ACCESS_KEY}"
          secure_api_token: "${SYSDIG_API_TOKEN}"
          api_url: "${SYSDIG_API_URL}"
          collector:
            host: "${SYSDIG_COLLECTOR_HOST}"
            port: ${SYSDIG_COLLECTOR_PORT}

        ssl:
          verify: false

        features:
          kubernetes_metadata:
            enabled: true
          admission_control:
            enabled: false
          posture:
            host_posture:
              enabled: false
            cluster_posture:
              enabled: false
          vulnerability_management:
            host_vulnerability_management:
              enabled: false
            container_vulnerability_management:
              enabled: false
            in_use:
              enabled: false
          detections:
            drift_control:
              enabled: false
            malware_control:
              enabled: false
            ml_policies:
              enabled: false
            kubernetes_audit:
              enabled: false
          investigations:
            activity_audit:
              enabled: false
            live_logs:
              enabled: false
            network_security:
              enabled: false
            captures:
              enabled: false
          respond:
            response_actions:
              enabled: false
            rapid_response:
              enabled: false
          monitor:
            prometheus:
              enabled: true
            kube_state_metrics:
              enabled: true
            kubernetes_events:
              enabled: true
            app_checks:
              enabled: false
            java_management_extensions:
              enabled: false
            statsd:
              enabled: false

        host:
          driver: universal_ebpf
          additional_settings:
            ssl_verify_certificate: false
          resources:
            shield:
              requests:
                memory: "256Mi"
                cpu: "100m"
              limits:
                memory: "1Gi"
                cpu: "500m"
            kmodule:
              requests:
                memory: "256Mi"
                cpu: "100m"
              limits:
                memory: "1Gi"
                cpu: "500m"

        cluster:
          replica_count: 1
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          pod_disruption_budget:
            create: false
          additional_settings:
            log_level: debug

  destination:
    server: https://kubernetes.default.svc
    namespace: ${SYSDIG_NS}

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 1m
EOF

log "ArgoCD Application 생성 완료"

# ============================================================
# Step 4: ArgoCD 동기화 대기 및 상태 확인
# ============================================================
log "--- Step 4: ArgoCD 동기화 대기 ---"

log "ArgoCD가 Helm 차트를 렌더링하고 배포합니다..."
log "(ArgoCD 서버에 Helm이 내장되어 있어 로컬 Helm CLI는 불필요)"

# 동기화 상태를 폴링으로 확인 (argocd CLI 없이)
MAX_WAIT=300
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    SYNC_STATUS=$(kubectl get application sysdig-shield-test -n "$ARGOCD_NS" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl get application sysdig-shield-test -n "$ARGOCD_NS" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    PHASE=$(kubectl get application sysdig-shield-test -n "$ARGOCD_NS" \
        -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "Unknown")

    log "Sync: $SYNC_STATUS | Health: $HEALTH_STATUS | Phase: $PHASE | (${ELAPSED}s/${MAX_WAIT}s)"

    if [[ "$SYNC_STATUS" == "Synced" && "$HEALTH_STATUS" == "Healthy" ]]; then
        log "ArgoCD 동기화 및 헬스체크 성공!"
        break
    fi

    if [[ "$PHASE" == "Failed" || "$PHASE" == "Error" ]]; then
        log "[WARN] 동기화 실패. ArgoCD 앱 상태를 확인합니다."
        break
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    log "[WARN] 타임아웃 (${MAX_WAIT}초). 파드가 아직 준비되지 않았을 수 있습니다."
fi

# ============================================================
# Step 5: 배포 결과 확인
# ============================================================
log "--- Step 5: 배포 결과 확인 ---"

log ""
log "=== ArgoCD Application 상태 ==="
kubectl get application sysdig-shield-test -n "$ARGOCD_NS" \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision 2>&1 | tee -a "$LOG_FILE"

log ""
log "=== 파드 상태 ==="
kubectl get pods -n "$SYSDIG_NS" -o wide 2>&1 | tee -a "$LOG_FILE"

log ""
log "=== DaemonSet 상태 ==="
kubectl get daemonset -n "$SYSDIG_NS" 2>&1 | tee -a "$LOG_FILE"

log ""
log "=== Deployment 상태 ==="
kubectl get deployment -n "$SYSDIG_NS" 2>&1 | tee -a "$LOG_FILE"

log ""
log "=== 전체 리소스 ==="
kubectl get all -n "$SYSDIG_NS" 2>&1 | tee -a "$LOG_FILE"

# Agent 로그 확인
AGENT_POD=$(kubectl get pods -n "$SYSDIG_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$AGENT_POD" ]]; then
    log ""
    log "=== 첫 번째 파드 로그 (최근 30줄) ==="
    kubectl logs "$AGENT_POD" -n "$SYSDIG_NS" --tail=30 2>&1 | tee -a "$LOG_FILE" || log "아직 로그가 없습니다."
fi

# ArgoCD 앱 상세 조건 확인
log ""
log "=== ArgoCD 동기화 상세 ==="
kubectl get application sysdig-shield-test -n "$ARGOCD_NS" \
    -o jsonpath='{.status.operationState.message}' 2>/dev/null | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

log ""
log "============================================================"
log "테스트 완료!"
log "============================================================"
log ""
log "확인 명령어:"
log "  파드 상태:      kubectl get pods -n $SYSDIG_NS -w"
log "  Agent 로그:     kubectl logs -f <POD_NAME> -n $SYSDIG_NS"
log "  ArgoCD 앱:      kubectl get application -n $ARGOCD_NS"
log "  ArgoCD UI:      kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8080:443"
log "  ArgoCD 로그인:  admin / $ARGOCD_INITIAL_PW"
log ""
log "정리: bash test/minikube-test-deploy.sh cleanup"
log "로그: $LOG_FILE"
