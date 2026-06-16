---
name: pharos-allowance-guard
description: >
  ERC20 approval security auditor for AI agents on the Pharos blockchain — the
  "guard your wallet" companion to pharos-approvals. Invoke when the user wants to
  audit, review, list, or clean up token approvals on Pharos ("which spenders can
  touch my tokens?", "find risky/unlimited approvals", "revoke all approvals for this
  token", "pharos", "PHRS", "atlantic-testnet"). Scans Approval event logs, resolves
  each spender's live allowance, flags unlimited/risky ones, and batch-revokes the
  spenders the user chooses. Reads are gas-free; revokes reuse the pharos-approvals
  revoke flow with full pre-checks.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos Allowance Guard

The security auditor for ERC20 approvals on Pharos. Unlimited and stale approvals are
the #1 wallet-drainer vector — this skill lets an agent **find every spender** a user
has approved for a token, **flag the risky ones**, and **batch-revoke** them. The
natural companion to `pharos-approvals` (which grants allowances safely; this one
audits and cleans them up).

## Prerequisites

1. **Foundry (`cast`)** installed (`which cast`; install per `pharos-approvals` if missing).
2. **Private key** only for the revoke step (`--private-key $PRIVATE_KEY`). The audit
   itself is read-only and needs no key.

## Network Configuration

Read `assets/networks.json`, default `atlantic-testnet`, fill `rpcUrl` into `--rpc-url`.

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
```

## Capability Index

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| List every spender I've approved for a token | scan `Approval` event logs + resolve live allowance | → `references/audit.md#audit-list-spenders` |
| Flag unlimited / risky approvals | classify live allowance values | → `references/audit.md#flag-classify-risk` |
| Revoke several approvals at once | batch `approve(spender, 0)` | → `references/audit.md#batch-revoke` |

## Security Reminders

- An audit reflects **live, on-chain allowances** (not just historical events) — always
  resolve the current `allowance` for each discovered spender; an event may have been
  superseded by a later revoke.
- Treat any `allowance == type(uint256).max` as **unlimited (⚠️ high risk)** and
  recommend revoking unless the user actively uses that spender.
- Revokes are writes: run the full Write Operation Pre-checks (see `pharos-approvals`
  SKILL.md), confirm the network, and never log keys.

## Write Operation Pre-checks (revoke only)

Same protocol as the rest of the suite: private-key check → derive + confirm sender →
confirm network (warn on mainnet) → preflight each `approve(spender, 0)` before
broadcasting.
