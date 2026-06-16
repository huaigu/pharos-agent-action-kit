---
name: pharos-approvals
description: >
  ERC20 approval lifecycle for AI agents on the Pharos blockchain — the keystone
  primitive the official pharos-skill-engine is missing. Invoke whenever the user
  wants to approve a spender, check or read an allowance, revoke/reset an approval,
  or move tokens via transferFrom on Pharos ("pharos", "PHRS", "PROS",
  "atlantic-testnet"). Required before ANY DeFi action (swap, stake, deposit) since
  those all need an approval first. Every write is pre-flighted with a cast call
  dry-run and revert decode before broadcasting. Composes on top of the official
  pharos-skill-engine; do not attempt Pharos token approvals without this skill.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos Approvals

The ERC20 **approval lifecycle** for Pharos agents: `approve`, read `allowance`,
`revoke` (reset to zero), and `transferFrom` — each guarded by a **preflight
dry-run** before broadcasting. This is the primitive the official
[`pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine) does
not ship, yet every DeFi interaction (swap / stake / deposit) needs it first.

## Prerequisites

1. **Foundry (`cast`) must be installed.** Run `which cast`. If not found, install:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   source ~/.zshenv && foundryup
   cast --version
   ```
   If installation fails, inform the user and STOP. Do not fall back to raw JSON-RPC.
2. **Private key** for write operations (`approve`, `revoke`, `transferFrom`), via
   `--private-key $PRIVATE_KEY`. Reads (`allowance`) need no key.

## Network Configuration

Network info lives in `assets/networks.json` (Atlantic testnet + mainnet), identical
in shape to the official engine.

- **Default**: `atlantic-testnet` (used when the user does not specify a network).
- **Switch**: when the user says `mainnet`, read that entry's `rpcUrl`.
- Read the target network and fill `rpcUrl` into each command's `--rpc-url`:
  ```bash
  RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
  ```

## Capability Index

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| Approve a spender to spend my token | `cast send approve(address,uint256)` | → `references/approve.md#approve-grant-an-allowance` |
| Check how much a spender is allowed | `cast call allowance(address,address)` | → `references/approve.md#allowance-read-an-approval` |
| Revoke / reset an approval to zero | `cast send approve(spender,0)` | → `references/approve.md#revoke-reset-an-allowance-to-zero` |
| Move tokens via an existing allowance | `cast send transferFrom(address,address,uint256)` | → `references/approve.md#transferfrom-spend-an-allowance` |
| Dry-run / simulate any write before sending | `cast call` + revert decode | → `references/preflight.md` |

## Security Reminders

- **Prefer exact-amount approvals.** Unlimited approvals (`type(uint256).max`) are a
  primary wallet-drainer vector. Default to the exact amount the user needs; only use
  unlimited when the user explicitly asks, and warn them when you do.
- **Never expose private keys** in logs, chat, or version control. Pass explicitly via
  `--private-key $PRIVATE_KEY` (cast does NOT auto-read env vars).
- **Confirm the network** before every write. Warn prominently and re-confirm for
  `mainnet`.

## Write Operation Pre-checks (required for every write)

Before any `approve` / `revoke` / `transferFrom`:

1. **Private key set?**
   ```bash
   [ -n "$PRIVATE_KEY" ] && echo "PRIVATE_KEY is set" || echo "PRIVATE_KEY is not set"
   ```
   If not set, tell the user to `export PRIVATE_KEY=<key>` and stop.
2. **Derive + confirm the sender address:**
   ```bash
   cast wallet address --private-key $PRIVATE_KEY
   ```
3. **Confirm the target network** (read name/type from `assets/networks.json`). For
   `mainnet`, warn and require explicit re-confirmation.
4. **Preflight the write** (`references/preflight.md`) — simulate with `cast call`
   and decode any revert BEFORE broadcasting.

## General Error Handling

| Error Signature | Handling |
|---|---|
| `invalid address` | Check address format (0x + 40 hex chars) |
| `execution reverted` | Decode and display the revert reason (see `references/preflight.md`) |
| missing `--private-key` | Prompt the user to pass `--private-key $PRIVATE_KEY` |
| `insufficient funds` | Insufficient gas balance; show current balance |
| `nonce too low` | Suggest waiting or specifying a nonce |
| `assets/networks.json` unreadable | Config missing/invalid |
