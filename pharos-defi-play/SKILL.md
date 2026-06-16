---
name: pharos-defi-play
description: >
  Composed multi-step DeFi "plays" for AI agents on the Pharos blockchain — turns the
  raw primitives of the official pharos-skill-engine plus the pharos-approvals skill
  into safe, end-to-end sequences. Invoke when the user wants to do a multi-step
  on-chain action that needs an approval first: "approve then deposit", "stake my
  tokens", "approve then call <method>", or the worked vault deposit/withdraw demo on
  Pharos ("pharos", "PHRS", "atlantic-testnet"). Each step is pre-flighted before
  broadcast and the next step is simulated against the previous step's result, so a
  play aborts cleanly instead of stranding the user mid-sequence.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos DeFi Play

Composed, multi-step **on-chain plays** for Pharos agents. A "play" is a guarded
sequence of primitives — the canonical one being **approve → call**, the building
block of every swap / stake / deposit. This skill sequences those steps safely
(preflight each, abort on revert) and ships one worked **vault deposit/withdraw**
play with a self-contained `MockVault` demo target.

Builds on:
- the official [`pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine) (deploy, write, query), and
- **`pharos-approvals`** (the approval lifecycle + the preflight convention).

## Prerequisites

1. **Foundry (`cast` + `forge`)** installed (`which cast`; install per the
   `pharos-approvals` SKILL.md if missing).
2. **Private key** via `--private-key $PRIVATE_KEY` for the write steps.
3. The **`pharos-approvals`** skill available — this skill reuses its `approve` and
   `preflight` references rather than redefining them.

## Network Configuration

Same as the rest of the suite: read `assets/networks.json`, default
`atlantic-testnet`, fill `rpcUrl` into `--rpc-url`. Mainnet requires an explicit warning.

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
```

## Capability Index

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| Approve then call any contract method (deposit/stake/...) | guarded approve-then-call sequence | → `references/play.md#approve-then-call-generic` |
| Deposit a token into a vault and confirm shares | worked vault play | → `references/play.md#vault-deposit-worked-play` |
| Withdraw a token from the vault | worked vault play | → `references/play.md#vault-withdraw` |
| Deploy the demo MockVault target | `forge create` / `forge script` | → `references/play.md#deploy-the-mockvault-demo-target` |

## Security Reminders

- **Approve the exact amount the play needs.** Do not default to unlimited approvals
  just because a play follows the approval — scope the allowance to the deposit/stake
  amount.
- **Preflight every step**, and preflight step *N+1* against the state produced by
  step *N*. If any preflight reverts, STOP and report — do not leave the user approved
  but un-deposited.
- Confirm the network before writes; warn + re-confirm on mainnet. Never log keys.

## Write Operation Pre-checks

Identical to `pharos-approvals` (`SKILL.md`): private-key check → derive + confirm
sender → confirm network → preflight. Run them once before starting a play; re-derive
the sender address only, not re-confirm, between steps of the same play.
