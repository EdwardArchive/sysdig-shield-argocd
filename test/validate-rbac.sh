#!/bin/bash
# RBAC 검증 스크립트
# Helm 차트(sysdig/shield)가 생성하는 RBAC 리소스를 검증합니다.

set -e

NAMESPACE="${1:-sysdig-shield}"

echo "RBAC 정책 검증 중... (네임스페이스: $NAMESPACE)"

# 와일드카드 권한 확인
echo "와일드카드 권한 확인 중..."
WILDCARDS=$(kubectl get clusterroles -o json | jq -r '.items[] | select(.metadata.name | contains("sysdig")) | select(.rules[]? | select(.resources[]? == "*" or .verbs[]? == "*")) | .metadata.name')

if [ -n "$WILDCARDS" ]; then
    echo "[FAIL] 와일드카드 권한 발견: $WILDCARDS"
    exit 1
else
    echo "[PASS] 와일드카드 권한 없음"
fi

# ServiceAccount 존재 확인 (Helm 차트가 생성하는 이름 패턴)
echo "ServiceAccount 확인 중..."
SA_COUNT=$(kubectl get serviceaccounts -n "$NAMESPACE" -o json | jq '[.items[] | select(.metadata.name | contains("sysdig") or contains("shield"))] | length')

if [ "$SA_COUNT" -gt 0 ]; then
    echo "[PASS] Sysdig ServiceAccount ${SA_COUNT}개 발견"
    kubectl get serviceaccounts -n "$NAMESPACE" -o name | grep -E "sysdig|shield" | while read sa; do
        echo "  - $sa"
    done
else
    echo "[FAIL] Sysdig ServiceAccount를 찾을 수 없음"
    exit 1
fi

# ClusterRole 존재 확인
echo "ClusterRole 확인 중..."
CR_COUNT=$(kubectl get clusterroles -o json | jq '[.items[] | select(.metadata.name | contains("sysdig") or contains("shield"))] | length')

if [ "$CR_COUNT" -gt 0 ]; then
    echo "[PASS] Sysdig ClusterRole ${CR_COUNT}개 발견"
else
    echo "[FAIL] Sysdig ClusterRole을 찾을 수 없음"
    exit 1
fi

echo "[PASS] RBAC 검증 완료"
