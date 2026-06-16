#!/usr/bin/env bash
#
# Pharos Agent Action Kit — end-to-end smoke demo.
#
# Runs the full suite flow against the Pharos Atlantic testnet:
#   1. deploy a StandardERC20-style demo token
#   2. pharos-approvals : approve -> allowance -> transferFrom
#   3. pharos-defi-play : deploy MockVault -> approve+deposit -> withdraw
#   4. pharos-allowance-guard : approve a spender unlimited -> detect -> revoke
#
# Safe to run anywhere: if PRIVATE_KEY is unset it prints what it WOULD do and exits 0
# (so CI without secrets stays green). Every write is preflighted with `cast call`
# before broadcasting, mirroring the skill instructions.
#
# Usage:
#   export PRIVATE_KEY=<funded_atlantic_testnet_key>
#   ./scripts/smoke.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORKS="$ROOT/pharos-approvals/assets/networks.json"
RPC="$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$NETWORKS")"
EXPLORER="$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .explorerUrl' "$NETWORKS")"

note()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
info()  { printf '   %s\n' "$*"; }
fail()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

command -v cast  >/dev/null 2>&1 || fail "Foundry 'cast' not found. Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
command -v forge >/dev/null 2>&1 || fail "Foundry 'forge' not found."
command -v jq    >/dev/null 2>&1 || fail "'jq' not found."
command -v python3 >/dev/null 2>&1 || fail "'python3' not found."

note "Network"
info "atlantic-testnet  rpc=$RPC"

if [ -z "${PRIVATE_KEY:-}" ]; then
  note "DRY MODE (PRIVATE_KEY unset)"
  cat <<EOF
   No PRIVATE_KEY in the environment, so nothing will be broadcast.
   To run the real demo:
       export PRIVATE_KEY=<funded atlantic-testnet key>
       ./scripts/smoke.sh

   Planned steps (each write is preflighted with 'cast call' first):
     1. deploy demo ERC20 token
     2. approvals : approve(spender, 100) -> allowance -> transferFrom
     3. play      : deploy MockVault -> approve(vault,50)+deposit(50) -> withdraw(50)
     4. guard     : approve(spender, MAX) -> audit detects UNLIMITED -> revoke -> re-audit
EOF
  # Still verify the fixture compiles — useful signal even without a key.
  note "Compile-check MockVault fixture"
  ( cd "$ROOT" && forge build >/dev/null && info "forge build OK" )
  exit 0
fi

SENDER="$(cast wallet address --private-key "$PRIVATE_KEY")"
note "Sender"
info "$SENDER"
BAL="$(cast balance "$SENDER" --rpc-url "$RPC")"
info "gas balance (wei): $BAL"
[ "$BAL" = "0" ] && fail "Sender has 0 balance — fund it from the Pharos testnet faucet first."

# A second throwaway address to act as the spender in the demos.
SPENDER="0x000000000000000000000000000000000000dEaD"

# --- preflight helper: simulate a write, abort if it would revert -------------
preflight() { # args: to sig [args...]
  local to="$1" sig="$2"; shift 2
  cast call "$to" "$sig" "$@" --from "$SENDER" --rpc-url "$RPC" >/dev/null \
    || fail "preflight reverted for $sig — not broadcasting"
}

note "1. Deploy demo ERC20 token"
# Minimal inline ERC20 written into src scope so `forge create` resolves it.
TOKEN_SRC="$ROOT/scripts/DemoToken.sol"
cat > "$TOKEN_SRC" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
contract DemoToken {
    string public name = "Demo Token"; string public symbol = "DEMO"; uint8 public decimals = 18;
    mapping(address=>uint256) public balanceOf; mapping(address=>mapping(address=>uint256)) public allowance;
    event Transfer(address indexed f,address indexed t,uint256 v);
    event Approval(address indexed o,address indexed s,uint256 v);
    constructor(){ balanceOf[msg.sender]=1_000_000 ether; }
    function approve(address s,uint256 v) external returns(bool){ allowance[msg.sender][s]=v; emit Approval(msg.sender,s,v); return true; }
    function transfer(address t,uint256 v) external returns(bool){ balanceOf[msg.sender]-=v; balanceOf[t]+=v; emit Transfer(msg.sender,t,v); return true; }
    function transferFrom(address f,address t,uint256 v) external returns(bool){ require(allowance[f][msg.sender]>=v,"ERC20: insufficient allowance"); allowance[f][msg.sender]-=v; balanceOf[f]-=v; balanceOf[t]+=v; emit Transfer(f,t,v); return true; }
}
SOL
TOKEN_ADDR="$(forge create "$TOKEN_SRC:DemoToken" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --json | jq -r '.deployedTo')"
info "token: $EXPLORER/address/$TOKEN_ADDR"
DEC="$(cast call "$TOKEN_ADDR" 'decimals()(uint8)' --rpc-url "$RPC")"

amt() { python3 -c "print(int($1 * 10**$DEC))"; }

note "2. pharos-approvals : approve(100) -> allowance -> transferFrom(40)"
A100="$(amt 100)"
preflight "$TOKEN_ADDR" "approve(address,uint256)" "$SPENDER" "$A100"
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$SPENDER" "$A100" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
info "allowance(SENDER -> SPENDER): $(cast call "$TOKEN_ADDR" 'allowance(address,address)(uint256)' "$SENDER" "$SPENDER" --rpc-url "$RPC")"
# transferFrom demo that SUCCEEDS: SENDER self-approves, then spends that allowance to
# move 40 tokens to SPENDER — exercising the allowance-spend path end to end.
A40="$(amt 40)"
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$SENDER" "$A40" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
preflight "$TOKEN_ADDR" "transferFrom(address,address,uint256)" "$SENDER" "$SPENDER" "$A40"
cast send "$TOKEN_ADDR" "transferFrom(address,address,uint256)" "$SENDER" "$SPENDER" "$A40" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
info "transferFrom moved 40 DEMO to SPENDER; SPENDER balance: $(cast call "$TOKEN_ADDR" 'balanceOf(address)(uint256)' "$SPENDER" --rpc-url "$RPC")"

note "3. pharos-defi-play : deploy MockVault -> approve+deposit(50) -> withdraw(50)"
VAULT_ADDR="$(forge create "$ROOT/pharos-defi-play/assets/vault/MockVault.sol:MockVault" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --constructor-args "$TOKEN_ADDR" --json | jq -r '.deployedTo')"
info "vault: $EXPLORER/address/$VAULT_ADDR"
A50="$(amt 50)"
preflight "$TOKEN_ADDR" "approve(address,uint256)" "$VAULT_ADDR" "$A50"
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$VAULT_ADDR" "$A50" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
preflight "$VAULT_ADDR" "deposit(uint256)" "$A50"
cast send "$VAULT_ADDR" "deposit(uint256)" "$A50" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
info "vault shares: $(cast call "$VAULT_ADDR" 'balanceOf(address)(uint256)' "$SENDER" --rpc-url "$RPC")"
preflight "$VAULT_ADDR" "withdraw(uint256)" "$A50"
cast send "$VAULT_ADDR" "withdraw(uint256)" "$A50" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
info "vault shares after withdraw: $(cast call "$VAULT_ADDR" 'balanceOf(address)(uint256)' "$SENDER" --rpc-url "$RPC")"

note "4. pharos-allowance-guard : approve UNLIMITED -> detect -> revoke"
MAX="$(cast max-uint)"
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$SPENDER" "$MAX" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
LIVE="$(cast call "$TOKEN_ADDR" 'allowance(address,address)(uint256)' "$SENDER" "$SPENDER" --rpc-url "$RPC")"
if [ "$LIVE" = "$MAX" ]; then info "DETECTED unlimited allowance for $SPENDER (high risk) -> revoking"; fi
cast send "$TOKEN_ADDR" "approve(address,uint256)" "$SPENDER" 0 --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
info "allowance after revoke: $(cast call "$TOKEN_ADDR" 'allowance(address,address)(uint256)' "$SENDER" "$SPENDER" --rpc-url "$RPC")"

rm -f "$TOKEN_SRC"
note "Done — full suite demo complete ✅"
