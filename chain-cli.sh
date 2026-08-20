#!/usr/bin/env bash
set -euo pipefail

RPC_BASE="https://mainnet.base.org"
RPC_ETH="https://eth.llamarpc.com"
RPC_BASE_SEPOLIA="https://sepolia.base.org"

rpc_url() {
  case "${1:-base}" in
    base) echo "$RPC_BASE" ;;
    ethereum|eth|mainnet) echo "$RPC_ETH" ;;
    base-sepolia|sepolia) echo "$RPC_BASE_SEPOLIA" ;;
    *) echo "ERROR: unknown network: $1" >&2; exit 1 ;;
  esac
}

rpc() {
  local url="$1"
  local method="$2"
  local params="${3:-[]}"
  curl -fsS --max-time 20 \
    -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
    "$url"
}

hex_to_dec() {
  local h="${1#0x}"
  if command -v bc >/dev/null 2>&1; then
    printf '%s\n' "$((16#$h))"
  else
    printf '%d\n' "0x$h"
  fi
}

wei_to_eth() {
  local wei="$1"
  if command -v bc >/dev/null 2>&1; then
    printf '%s\n' "$wei" | awk '{printf "%.18f\n", $1/1000000000000000000}'
  else
    python - "$wei" <<'PY'
import sys
print(f"{int(sys.argv[1])/10**18:.18f}")
PY
  fi
}

usage() {
  cat <<'EOF'
ChainCLI — Lightweight JSON-RPC CLI

Usage:
  chain base block
  chain base chainid
  chain base balance ADDRESS
  chain base balance ADDRESS --eth
  chain ethereum block
  chain base-sepolia block
  chain base chainid --json
  chain base balance ADDRESS --json

Networks:
  base
  ethereum
  base-sepolia
EOF
}

[[ $# -ge 2 ]] || { usage; exit 1; }

NETWORK="$1"
COMMAND="$2"
RPC_URL="$(rpc_url "$NETWORK")"

case "$COMMAND" in
  block)
    result="$(rpc "$RPC_URL" eth_blockNumber)"
    if [[ "${3:-}" == "--json" ]]; then
      printf '%s\n' "$result"
    else
      hex="$(printf '%s' "$result" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"
      [[ -n "$hex" ]] || { echo "$result"; exit 1; }
      echo "Network: $NETWORK"
      echo "Latest block: $(hex_to_dec "$hex")"
    fi
    ;;

  chainid)
    result="$(rpc "$RPC_URL" eth_chainId)"
    if [[ "${3:-}" == "--json" ]]; then
      printf '%s\n' "$result"
    else
      hex="$(printf '%s' "$result" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"
      echo "Network: $NETWORK"
      echo "Chain ID: $(hex_to_dec "$hex")"
    fi
    ;;

  balance)
    ADDRESS="${3:-}"
    FORMAT="${4:-}"
    [[ "$ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]] || {
      echo "ERROR: invalid Ethereum address" >&2
      exit 1
    }

    result="$(rpc "$RPC_URL" eth_getBalance "[\"$ADDRESS\",\"latest\"]")"

    if [[ "$FORMAT" == "--json" ]]; then
      printf '%s\n' "$result"
      exit 0
    fi

    hex="$(printf '%s' "$result" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"
    [[ -n "$hex" ]] || { echo "$result"; exit 1; }

    wei="$(hex_to_dec "$hex")"

    if [[ "$FORMAT" == "--eth" ]]; then
      echo "Network: $NETWORK"
      echo "Address: $ADDRESS"
      echo "Balance: $(wei_to_eth "$wei") ETH"
    else
      echo "Network: $NETWORK"
      echo "Address: $ADDRESS"
      echo "Balance: $wei Wei"
    fi
    ;;

  *)
    usage
    exit 1
    ;;
esac
