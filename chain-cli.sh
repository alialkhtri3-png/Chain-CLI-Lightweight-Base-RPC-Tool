#!/usr/bin/env bash

set -u

VERSION="0.3.0"

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
  code <address>
  gas
  nonce <address>
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


decode_abi_string() {
  local hex="${1:-}"
  hex="${hex#0x}"

  [[ -n "$hex" ]] || return 1
  (( ${#hex} % 2 == 0 )) || return 1

  local data=""

  # ABI dynamic string:
  # offset(32 bytes) + length(32 bytes) + data
  if (( ${#hex} >= 128 )); then
    local length_hex="${hex:64:64}"

    if [[ "$length_hex" =~ ^[0-9a-fA-F]+$ ]]; then
      local length=$((16#$length_hex))

      if (( length >= 0 && length <= 4096 )); then
        data="${hex:128:$((length * 2))}"
      fi
    fi
  fi

  # bytes32/static-string fallback
  if [[ -z "$data" ]]; then
    data="${hex%%00*}"
  fi

  [[ -n "$data" ]] || return 1
  (( ${#data} % 2 == 0 )) || return 1

  printf '%s' "$data" | xxd -r -p
}


cmd_code() {
  local network="$1"
  local rpc_url="$2"
  local address="$3"

  [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "Invalid address"

  local response code
  response="$(rpc "$rpc_url" "eth_getCode" "[\"$address\",\"latest\"]")"
  code="$(printf '%s' "$response" | jq -r '.result // empty')"

  [[ -n "$code" ]] || die "eth_getCode failed"

  local type="EOA"
  if [[ "$code" != "0x" && "$code" != "0x0" ]]; then
    type="CONTRACT"
  fi

  if [[ "$JSON" == true ]]; then
    jq -n \
      --arg network "$network" \
      --arg address "$address" \
      --arg type "$type" \
      --arg code "$code" \
      '{
        network:$network,
        address:$address,
        type:$type,
        code:$code
      }'
  else
    echo "Network: $network"
    echo "Address: $address"
    echo "Type:    $type"
    echo "Code:    $code"
  fi
}

cmd_gas() {
  local network="$1"
  local rpc_url="$2"

  local response gas_price
  response="$(rpc "$rpc_url" "eth_gasPrice" "[]")"
  gas_price="$(printf '%s' "$response" | jq -r '.result // empty')"

  [[ -n "$gas_price" ]] || die "eth_gasPrice failed"

  local wei="${gas_price#0x}"
  local gas_dec=$((16#$wei))

  if [[ "$JSON" == true ]]; then
    jq -n \
      --arg network "$network" \
      --arg raw "$gas_price" \
      --arg wei "$gas_dec" \
      '{
        network:$network,
        gasPriceHex:$raw,
        gasPriceWei:$wei
      }'
  else
    echo "Network:      $network"
    echo "Gas Price:    $gas_dec Wei"
    echo "Gas Price Hex: $gas_price"
  fi
}

cmd_nonce() {
  local network="$1"
  local rpc_url="$2"
  local address="$3"

  [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "Invalid address"

  local response nonce_hex nonce
  response="$(rpc "$rpc_url" "eth_getTransactionCount" "[\"$address\",\"latest\"]")"
  nonce_hex="$(printf '%s' "$response" | jq -r '.result // empty')"

  [[ -n "$nonce_hex" ]] || die "eth_getTransactionCount failed"

  nonce=$((16#${nonce_hex#0x}))

  if [[ "$JSON" == true ]]; then
    jq -n \
      --arg network "$network" \
      --arg address "$address" \
      --arg hex "$nonce_hex" \
      --argjson nonce "$nonce" \
      '{
        network:$network,
        address:$address,
        nonce:$nonce,
        nonceHex:$hex
      }'
  else
    echo "Network: $network"
    echo "Address: $address"
    echo "Nonce:   $nonce"
    echo "Hex:     $nonce_hex"
  fi
}

cmd_erc20() {
  local network="$1"
  local rpc_url="$2"
  local token="$3"
  local address="$4"
  local mode="${5:-}"

  [[ "$token" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "Invalid ERC-20 token address"
  [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "Invalid wallet address"

  local balance_data decimals_data symbol_data name_data
  local balance_hex decimals_hex symbol_hex name_hex
  local balance_raw decimals symbol name

  balance_data="$(rpc "$rpc_url" "eth_call" "[{\"to\":\"$token\",\"data\":\"0x70a08231000000000000000000000000${address:2}\"},\"latest\"]")"
  decimals_data="$(rpc "$rpc_url" "eth_call" "[{\"to\":\"$token\",\"data\":\"0x313ce567\"},\"latest\"]")"
  symbol_data="$(rpc "$rpc_url" "eth_call" "[{\"to\":\"$token\",\"data\":\"0x95d89b41\"},\"latest\"]")"
  name_data="$(rpc "$rpc_url" "eth_call" "[{\"to\":\"$token\",\"data\":\"0x06fdde03\"},\"latest\"]")"

  balance_hex="$(printf '%s' "$balance_data" | jq -r '.result // empty')"
  decimals_hex="$(printf '%s' "$decimals_data" | jq -r '.result // empty')"
  symbol_hex="$(printf '%s' "$symbol_data" | jq -r '.result // empty')"
  name_hex="$(printf '%s' "$name_data" | jq -r '.result // empty')"

  if [[ -z "$balance_hex" || "$balance_hex" == "0x" ]]; then
    die "ERC-20 balanceOf returned empty result: token may not be an ERC-20 contract"
  fi

  if [[ -z "$decimals_hex" || "$decimals_hex" == "0x" ]]; then
    die "ERC-20 decimals() returned empty result: token may not be an ERC-20 contract"
  fi

  balance_raw="$((16#${balance_hex#0x}))"
  decimals="$((16#${decimals_hex#0x}))"

  symbol="$(decode_abi_string "$symbol_hex" 2>/dev/null || true)"
  name="$(decode_abi_string "$name_hex" 2>/dev/null || true)"

  [[ -n "$symbol" ]] || symbol="UNKNOWN"
  [[ -n "$name" ]] || name="UNKNOWN"

  local formatted
  if (( decimals > 0 )); then
    local raw="$balance_raw"
    local len="${#raw}"

    if (( len <= decimals )); then
      raw="$(printf '%0*s' $((decimals + 1 - len)) '' | tr ' ' '0')$raw"
      len="${#raw}"
    fi

    local whole="${raw:0:$((len - decimals))}"
    local frac="${raw:$((len - decimals))}"
    frac="${frac%"${frac##*[!0]}"}"

    if [[ -z "$frac" ]]; then
      formatted="$whole"
    else
      formatted="$whole.$frac"
    fi
  else
    formatted="$balance_raw"
  fi

  if [[ "$mode" == "--json" ]]; then
    jq -n \
      --arg network "$network" \
      --arg token "$token" \
      --arg address "$address" \
      --arg name "$name" \
      --arg symbol "$symbol" \
      --argjson decimals "$decimals" \
      --arg raw "$balance_raw" \
      --arg balance "$formatted" \
      '{
        network:$network,
        token:$token,
        address:$address,
        name:$name,
        symbol:$symbol,
        decimals:$decimals,
        balanceRaw:$raw,
        balance:$balance
      }'
  else
    echo "Network: $network"
    echo "Token:   $token"
    echo "Name:    $name"
    echo "Symbol:  $symbol"
    echo "Decimals: $decimals"
    echo "Balance: $formatted $symbol"
    echo "Raw:     $balance_raw"
  fi
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

      if [[ "$JSON" == true ]]; then
        cmd_erc20 "$network" "$rpc_url" "$token" "$address" "--json"
      else
        cmd_erc20 "$network" "$rpc_url" "$token" "$address"
      fi
      ;;

    code)
      [ "$#" -ge 1 ] || die "Usage: chain $network code <address>"

      local address="$1"
      shift

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_code "$network" "$rpc_url" "$address"
      ;;

    gas)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_gas "$network" "$rpc_url"
      ;;

    nonce)
      [ "$#" -ge 1 ] || die "Usage: chain $network nonce <address>"

      local address="$1"
      shift

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --json) JSON=true ;;
          *) die "Unknown option: $1" ;;
        esac
        shift
      done

      cmd_nonce "$network" "$rpc_url" "$address"
      ;;

    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
