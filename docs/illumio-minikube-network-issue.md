# Illumio VEN + minikube 네트워크 장애 분석

> **발생일**: 2026-03-31
> **환경**: Ubuntu Linux, minikube (Docker 드라이버), Illumio VEN 에이전트

## 증상

minikube 내부에서 외부 인터넷(quay.io, Docker Hub 등)에 접근할 수 없어 컨테이너 이미지 Pull이 실패합니다.

```
Failed to pull image "quay.io/argoproj/argocd:v3.3.6":
  Error response from daemon: Get "https://quay.io/v2/":
  net/http: request canceled while waiting for connection
```

- `docker exec minikube ping 8.8.8.8` → 100% packet loss
- DNS 해석은 정상 (`nslookup quay.io` 성공)
- 호스트에서는 외부 접근 정상 (`curl https://quay.io/v2/` → 401)

## 근본 원인

### 문제 1: iptables FORWARD 체인

Illumio VEN이 iptables FORWARD 체인의 **첫 번째 규칙**으로 `ILO-FILTER-FORWARD`를 삽입합니다. 이 체인은 `goto` 지시어를 사용하여 여러 하위 체인을 순회합니다:

```
FORWARD → ILO-FILTER-FORWARD (goto)
  → ILO-FILTER-FORWARD-TCP-IN (goto)
    → ILO-FILTER-FORWARD-TCP-OUT (goto)
      → ILO-FILTER-FORWARD-OTHER-IN (goto)
        → ILO-FILTER-FORWARD-OTHER-OUT (goto)
          → ILO-FILTER-FORWARD-USR (goto)
            → ILO-FILTER-ACTION-08000004 → ACCEPT
```

`goto`의 특성상, 체인이 끝나면 **호출한 체인의 다음 규칙이 아닌 상위 체인의 정책(policy)으로 돌아갑니다.** FORWARD 정책이 `DROP`이므로, ILO 체인에서 ACCEPT해도 Docker의 MASQUERADE 등 후속 규칙이 실행되지 않습니다.

> **참고**: `goto` vs `jump`
> - `jump (-j)`: 대상 체인 실행 후 **호출한 위치의 다음 규칙**으로 복귀
> - `goto (-g)`: 대상 체인 실행 후 **상위 체인의 정책(policy)**으로 이동 (복귀하지 않음)

### 문제 2: iptables NAT POSTROUTING 체인

같은 패턴이 NAT 테이블에서도 발생합니다:

```
POSTROUTING → ILO-NAT-POSTROUTING (goto)
  → ILO-NAT-POSTROUTING-USR (goto)
    → ACCEPT (MASQUERADE 없이 종료)
```

minikube 서브넷(192.168.49.0/24)에서 나가는 패킷이 **NAT 변환 없이** 사설 IP 그대로 외부로 전송되어, 응답 패킷이 돌아오지 못합니다.

### 체인 구조 요약

```
[FORWARD 체인 - policy DROP]
  1. ILO-FILTER-FORWARD (goto)  ← 모든 패킷을 가로챔
     └─ 최종: ACCEPT (goto 사용 → DROP policy로 이동 → 패킷 DROP)
  2. Docker ACCEPT 규칙들        ← 도달 불가
  3. DOCKER-USER                  ← 도달 불가

[NAT POSTROUTING - policy ACCEPT]
  1. ILO-NAT-POSTROUTING (goto)  ← 모든 패킷을 가로챔
     └─ 최종: ACCEPT (MASQUERADE 없이)
  2. MASQUERADE 규칙들             ← 도달 불가
```

## 해결 방법

### 방법 1: Illumio를 Idle 모드로 변경 (권장)

Illumio VEN을 Idle 모드로 설정하면 ILO iptables 규칙이 제거됩니다.

```bash
# Illumio PCE 콘솔에서 해당 워크로드의 정책 모드를 Idle로 변경
```

이 방법이 가장 깔끔하지만, 해당 호스트의 Illumio 보호가 비활성화됩니다.

### 방법 2: ILO 체인보다 앞에 규칙 삽입

Illumio가 규칙을 자동 재배치하므로 이 방법은 **일시적**입니다:

```bash
# NAT: minikube 서브넷 MASQUERADE (ILO 체인보다 먼저)
sudo iptables -t nat -I POSTROUTING 1 \
  -s 192.168.49.0/24 -o <외부인터페이스> -j MASQUERADE

# FORWARD: minikube 서브넷 허용 (ILO 체인보다 먼저)
sudo iptables -I FORWARD 1 \
  -s 192.168.49.0/24 -o <외부인터페이스> -j ACCEPT
sudo iptables -I FORWARD 1 \
  -i <외부인터페이스> -d 192.168.49.0/24 \
  -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

> Illumio VEN이 주기적으로 규칙을 재동기화하면 삽입한 규칙이 밀려날 수 있습니다.

### 방법 3: Illumio Visibility Only 모드에서 예외 설정

Illumio PCE에서 minikube 서브넷(192.168.49.0/24)에 대한 허용 규칙을 추가합니다:
- Source: 192.168.49.0/24
- Destination: Any
- Service: All
- Action: Allow

이렇게 하면 Illumio 보호를 유지하면서 minikube 트래픽만 허용할 수 있습니다.

## 영향 범위

이 문제는 **Illumio VEN이 설치된 모든 호스트에서 Docker bridge 네트워크를 사용하는 경우** 발생할 수 있습니다:

- minikube (Docker 드라이버)
- docker-compose 네트워크
- 커스텀 Docker bridge 네트워크

## 검증 방법

```bash
# minikube 내부에서 외부 연결 테스트
docker exec minikube ping -c 2 8.8.8.8
docker exec minikube curl -m 10 -s -o /dev/null -w '%{http_code}' https://quay.io/v2/

# 예상 결과:
# ping: 0% packet loss
# curl: 401 (정상 — 인증 필요 응답)
```

## 참고

- [Illumio VEN iptables 동작 방식](https://docs.illumio.com/)
- [iptables goto vs jump](https://ipset.netfilter.org/iptables-extensions.man.html)
- [Docker 네트워크와 iptables](https://docs.docker.com/network/packet-filtering-firewalls/)
