#!/usr/bin/env bash

set -u

VERSION="0.2.0"

RPC_BASE="https://mainnet.base.org"
RPC_BASE_SEPOLIA="https://sepolia.base.org"
RPC_ETH="https://ethereum.publicnode.com"

JSON=false

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
ChainCLI v$VERSION

Lightweight JSON-RPC CLI for EVM networks.

Usage:
  chain <network> <command> [args] [--json]

Networks:
  base
  base-sepolia
  ethereum

Commands:
  chainid
  block
  balance <address> [--eth]
  tx <tx_hash>
  erc20 <token> <address>

Examples:
  chain base chainid
  chain base block
  chain base balance 0xADDRESS --eth
  chain base tx 0xTXHASH
  chain base erc20 0xTOKEN 0xADDRESS
  chain base balance 0xADDRESS --json
  chain base chainid --json

Version:
  chain --version
EOF
}

rpc_for() {
  case "$1" in
    base) echo "$RPC_BASE" ;;
    base-sepolia) echo "$RPC_BASE_SEPOLIA" ;;
    ethereum|eth) echo "$RPC_ETH" ;;
    *) die "Unknown network: $1" ;;
  esac
}

rpc() {
  local url="$1"
  local method="$2"
  local params="$3"

  curl -fsS \
    --connect-timeout 10 \
    --max-time 30 \
    -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
    "$url" ||
    die "RPC request failed"
}

hex_to_decimal() {
  local value="$1"

  if command -v python >/dev/null 2>&1; then
    python - "$value" <<'PY'
import sys
v=sys.argv[1]
print(int(v,16))
PY
  elif command -v bc >/dev/null 2>&1; then
    printf '%s\n' "$value" | sed 's/^0x//' | xargs -I{} sh -c 'echo "ibase=16; {}" | bc'
  else
    die "Python or bc is required"
  fi
}

wei_to_eth() {
  python - "$1" <<'PY'
from decimal import Decimal, getcontext
import sys

getcontext().prec = 80
wei = int(sys.argv[1])
eth = Decimal(wei) / Decimal(10**18)

print(format(eth, 'f'))
PY
}

validate_address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]] ||
    die "Invalid Ethereum address"
}

validate_tx() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{64}$ ]] ||
    die "Invalid transaction hash"
}

json_result() {
  local result="$1"

  if [ "$JSON" = true ]; then
    echo "$result"
  else
    echo "$result"
  fi
}

cmd_chainid() {
  local network="$1"
  local rpc_url="$2"

  local response
  response="$(rpc "$rpc_url" eth_chainId '[]')"

  if [ "$JSON" = true ]; then
    echo "$response"
    return
  fi

  local chain_id
  chain_id="$(printf '%s' "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"

  [ -n "$chain_id" ] || die "Invalid RPC response"

  echo "Network: $network"
  echo "Chain ID: $(hex_to_decimal "$chain_id")"
}

cmd_block() {
  local network="$1"
  local rpc_url="$2"

  local response
  response="$(rpc "$rpc_url" eth_blockNumber '[]')"

  if [ "$JSON" = true ]; then
    echo "$response"
    return
  fi

  local block
  block="$(printf '%s' "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"

  [ -n "$block" ] || die "Invalid RPC response"

  echo "Network: $network"
  echo "Latest block: $(hex_to_decimal "$block")"
}

cmd_balance() {
  local network="$1"
  local rpc_url="$2"
  local address="$3"
  local eth="$4"

  validate_address "$address"

  local response
  response="$(rpc "$rpc_url" eth_getBalance "[\"$address\",\"latest\"]")"

  if [ "$JSON" = true ]; then
    echo "$response"
    return
  fi

  local balance
  balance="$(printf '%s' "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"

  [ -n "$balance" ] || die "Invalid RPC response"

  local decimal
  decimal="$(hex_to_decimal "$balance")"

  echo "Network: $network"
  echo "Address: $address"
  echo "Balance: $decimal Wei"

  if [ "$eth" = true ]; then
    echo "Balance: $(wei_to_eth "$decimal") ETH"
  fi
}

cmd_tx() {
  local network="$1"
  local rpc_url="$2"
  local hash="$3"

  validate_tx "$hash"

  local response
  response="$(rpc "$rpc_url" eth_getTransactionByHash "[\"$hash\"]")"

  if [ "$JSON" = true ]; then
    echo "$response"
    return
  fi

  local result
  result="$(printf '%s' "$response" | sed -n 's/.*"result":\(.*\)}$/\1/p')"

  [ -n "$result" ] || die "Transaction not found"

  echo "Network: $network"
  echo "Transaction: $hash"
  echo
  echo "$response"
}

cmd_erc20() {
  local network="$1"
  local rpc_url="$2"
  local token="$3"
  local address="$4"

  validate_address "$token"
  validate_address "$address"

  # balanceOf(address)
  # selector = 0x70a08231
  local padded
  padded="$(printf '%064s' "${address#0x}" | tr ' ' '0')"

  local data="0x70a08231$padded"

  local response
  response="$(rpc "$rpc_url" eth_call "[{\"to\":\"$token\",\"data\":\"$data\"},\"latest\"]")"

  if [ "$JSON" = true ]; then
    echo "$response"
    return
  fi

  local balance
  balance="$(printf '%s' "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"

  [ -n "$balance" ] || die "Invalid ERC-20 response"

  local decimal
  decimal="$(hex_to_decimal "$balance")"

  echo "Network: $network"
  echo "Token: $token"
  echo "Address: $address"
  echo "Raw balance: $decimal"
}

main() {

  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    echo "ChainCLI v$VERSION"
    exit 0
  fi

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
  fi

  local network="$1"
  shift

  local rpc_url
  rpc_url="$(rpc_for "$network")"

  local command="${1:-}"
  shift || true

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        JSON=true
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  case "$command" in

    chainid)
      cmd_chainid "$network" "$rpc_url"
      ;;

    block)
      cmd_block "$network" "$rpc_url"
      ;;

    balance)
      [ "$#" -ge 1 ] || die "Usage: chain $network balance <address> [--eth]"

      local address="$1"
      shift

      local eth=false

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --eth) eth=true ;;
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_balance "$network" "$rpc_url" "$address" "$eth"
      ;;

    tx)
      [ "$#" -ge 1 ] || die "Usage: chain $network tx <tx_hash>"

      local hash="$1"
      shift

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_tx "$network" "$rpc_url" "$hash"
      ;;

    erc20)
      [ "$#" -ge 2 ] ||
        die "Usage: chain $network erc20 <token> <address>"

      local token="$1"
      local address="$2"
      shift 2

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_erc20 "$network" "$rpc_url" "$token" "$address"
      ;;

    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
