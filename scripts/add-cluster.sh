#!/bin/bash
# ============================================================
# 새 클러스터 추가 스크립트
# 사용법: ./scripts/add-cluster.sh <클러스터명>
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTERS_DIR="$REPO_ROOT/helm-values/clusters"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/add-cluster-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

if [ $# -lt 1 ]; then
    log "ERROR: 클러스터명을 인자로 전달해주세요."
    echo "사용법: $0 <클러스터명>"
    echo "예시:   $0 woowa-cluster-payments"
    exit 1
fi

CLUSTER_NAME="$1"
CLUSTER_DIR="$CLUSTERS_DIR/$CLUSTER_NAME"

if [ -d "$CLUSTER_DIR" ]; then
    log "ERROR: 클러스터 '$CLUSTER_NAME' 디렉토리가 이미 존재합니다: $CLUSTER_DIR"
    exit 1
fi

log "INFO: 클러스터 '$CLUSTER_NAME' 디렉토리 생성 중..."
mkdir -p "$CLUSTER_DIR"

# 클러스터 공통 values
cat > "$CLUSTER_DIR/values.yaml" << EOF
# ============================================================
# 클러스터 고유 설정: $CLUSTER_NAME
# 생성일: $(date '+%Y-%m-%d')
# ============================================================

cluster_config:
  name: "$CLUSTER_NAME"
  tags:
    environment: production    # production | staging | dev
    team: ""                   # 담당 팀명
    cluster: "$CLUSTER_NAME"

host:
  tolerations:
  - operator: Exists
EOF

# 노드그룹별 values (빈 파일)
for NODEGROUP in small medium large; do
    cat > "$CLUSTER_DIR/values-$NODEGROUP.yaml" << EOF
# ============================================================
# 클러스터 + 노드그룹 고유 설정: $CLUSTER_NAME / $NODEGROUP
# 오버라이드가 필요한 경우에만 설정을 추가하세요.
# ============================================================
EOF
    log "INFO: $CLUSTER_DIR/values-$NODEGROUP.yaml 생성 완료"
done

log "INFO: 클러스터 '$CLUSTER_NAME' 추가 완료!"
log "INFO: 다음 단계:"
log "  1. $CLUSTER_DIR/values.yaml 에서 environment, team 등을 수정하세요."
log "  2. git add && git commit && git push 하면 ArgoCD가 자동으로 감지합니다."
