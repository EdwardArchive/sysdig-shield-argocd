#!/bin/bash
# 네트워크 정책 검증 스크립트
# Helm 차트(sysdig/shield)가 생성하는 NetworkPolicy를 검증합니다.

set -e

NAMESPACE="${1:-sysdig-shield}"

echo "네트워크 정책 검증 중... (네임스페이스: $NAMESPACE)"

# 네트워크 정책 존재 확인
NP_COUNT=$(kubectl get networkpolicies -n "$NAMESPACE" -o json | jq '.items | length')

if [ "$NP_COUNT" -gt 0 ]; then
    echo "[PASS] NetworkPolicy ${NP_COUNT}개 발견"
    kubectl get networkpolicies -n "$NAMESPACE" -o name | while read np; do
        echo "  - $np"
    done
else
    echo "[WARN] NetworkPolicy가 없습니다. Helm values에서 networkPolicy 설정을 확인하세요."
fi

# Default deny 정책 확인 (있는 경우)
if kubectl get networkpolicy -n "$NAMESPACE" -o json | jq -e '.items[] | select(.spec.policyTypes[] == "Ingress" and .spec.policyTypes[] == "Egress") | select(.spec.ingress == null and .spec.egress == null)' &>/dev/null; then
    echo "[PASS] Default deny 정책 존재"
else
    echo "[INFO] 명시적 default deny 정책 없음 (Helm 차트 설정에 따라 다를 수 있음)"
fi

# Egress 정책 확인 (Agent가 백엔드에 연결 가능해야 함)
if kubectl get networkpolicy -n "$NAMESPACE" -o json | jq -e '.items[] | select(.spec.egress != null)' &>/dev/null; then
    echo "[PASS] Egress 정책 존재"
else
    echo "[INFO] Egress 정책 없음"
fi

echo "[PASS] 네트워크 정책 검증 완료"
