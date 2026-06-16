# Pharos Agent Action Kit — Design

**Date:** 2026-06-16
**Status:** Approved (brainstorming)
**Hackathon:** Pharos Phase 1 (DoraHacks) — AI Agent / Skill Engine track

## 1. Summary

A suite of composable **Pharos Agent Skills** that layer on top of the official
[`PharosNetwork/pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine),
turning its raw primitives (read / write / deploy) into **safe, multi-step DeFi
actions**. The keystone is the ERC20 **approval lifecycle** the official engine is
missing — without it, no DeFi interaction (swap, stake, deposit) can even take its
first step.

One-liner: *"The agent layer that handles token approvals safely and executes
multi-step DeFi plays on Pharos."*

## 2. The Gap (why this, not a standalone contract)

The official engine ships four primitive layers:

- `query.md` — balances, tx status, contract reads, event logs
- `transaction.md` — native transfer, arbitrary contract write, gas estimate, batch airdrop
- `contract.md` — deploy, verify, ERC20 one-click deploy
- `script-gen.md` — JS/TS/Python script generation

It has **no ERC20 approval layer**: no `approve`, no `allowance` read, no `revoke`,
no `transferFrom`. The user's canonical example — *"swap my USDC then stake"* —
is impossible without `approve` first. This suite fills that gap and composes the
primitives into common on-chain plays, rather than competing with the crowded field
of x402 / NFT / DeFi-lens skills already submitted.

## 3. The Suite (MVP-ordered)

| # | Skill | One-liner | Role |
|---|-------|-----------|------|
| 1 | **`pharos-approvals`** | ERC20 approval lifecycle for agents — approve, allowance, revoke, transferFrom, each pre-flighted with a `cast call` dry-run + revert decode before broadcast. | Keystone / MVP |
| 2 | **`pharos-defi-play`** | Composed multi-step plays — a generic *approve-then-call* executor, demonstrated by a worked "approve → deposit → check shares → withdraw" vault play. | The "common play" |
| 3 | **`pharos-allowance-guard`** | Approval security auditor — scan `Approval` events, list every spender, flag unlimited allowances, batch-revoke risky ones. | Security / stretch |

Skills 1 + 3 need **no new contract** (pure composition with the official ERC20
deploy + event scanning). Skill 2 ships **one tiny `MockVault.sol` fixture** purely
as the demo *target* that pulls approved tokens — a test fixture, not "the product."

## 4. Architecture

Single public repo, one skill per directory, each independently installable and
self-contained (its own `SKILL.md`, `references/`, and `assets/networks.json`).

```
pharos-agent-action-kit/
├── README.md                      # suite overview, install, demo, scenarios
├── LICENSE                        # MIT
├── pharos-approvals/              # Skill 1 (keystone)
│   ├── SKILL.md                   # frontmatter + Capability Index
│   ├── references/
│   │   ├── approve.md             # approve / allowance / revoke / transferFrom
│   │   └── preflight.md           # cast call dry-run + revert decode convention
│   └── assets/networks.json       # self-contained (mirrors official values)
├── pharos-defi-play/              # Skill 2 (composition)
│   ├── SKILL.md
│   ├── references/play.md         # generic approve-then-call + worked vault play
│   └── assets/
│       ├── networks.json
│       └── vault/MockVault.sol    # demo fixture target (ERC4626-style, minimal)
└── pharos-allowance-guard/        # Skill 3 (security / stretch)
    ├── SKILL.md
    ├── references/audit.md        # scan Approval events, list, flag, batch-revoke
    └── assets/networks.json
```

### Design rules (match the official engine so they compose)

- Same frontmatter shape: `name`, `description`, `version`, `requires.anyBins: [cast, forge]`.
- Same write **pre-check protocol**: private-key check → derive address (`cast wallet address`) → network confirm → balance check.
- Same security posture: never log private keys; prefer **exact-amount** approvals over unlimited; explicit mainnet warning + re-confirmation.
- Every write capability carries a **preflight dry-run** (`cast call` with the same
  calldata, decode revert via `cast 4byte-decode` / `cast --to-ascii`) before
  `cast send` — the safety thread tying the suite together.
- Network config read from `assets/networks.json` exactly as the official engine does
  (`atlantic-testnet` default; `mainnet` opt-in). Values mirrored from the official
  `networks.json` so each skill works standalone.

### Capability Index (per skill, abbreviated)

**`pharos-approvals`**
| User Need | Capability | Reference |
|---|---|---|
| Approve a spender to spend my token | `cast send approve(address,uint256)` | `references/approve.md#approve` |
| Check how much a spender is allowed | `cast call allowance(address,address)` | `references/approve.md#allowance` |
| Revoke / reset an approval to zero | `cast send approve(spender,0)` | `references/approve.md#revoke` |
| Move tokens via an existing allowance | `cast send transferFrom(address,address,uint256)` | `references/approve.md#transferfrom` |
| Dry-run a write before sending | `cast call` + revert decode | `references/preflight.md` |

**`pharos-defi-play`**
| User Need | Capability | Reference |
|---|---|---|
| Approve then call any contract method (e.g. deposit/stake) | composed approve-then-call sequence | `references/play.md#approve-then-call` |
| Deposit a token into a vault and confirm shares | worked vault play | `references/play.md#vault-deposit` |
| Withdraw from the vault | worked vault play | `references/play.md#vault-withdraw` |

**`pharos-allowance-guard`**
| User Need | Capability | Reference |
|---|---|---|
| List every spender I've approved for a token | scan `Approval` event logs | `references/audit.md#audit` |
| Flag unlimited / risky approvals | classify allowance values | `references/audit.md#flag` |
| Revoke multiple approvals at once | batch `approve(spender,0)` | `references/audit.md#batch-revoke` |

## 5. Demo Flow (reliable on Atlantic testnet, no ecosystem dependency)

1. Deploy a `StandardERC20` via the official engine → token address.
2. **`pharos-approvals`**: `approve` a spender an exact amount → read `allowance` →
   `transferFrom` → confirm on explorer.
3. **`pharos-defi-play`**: deploy `MockVault`, run *"deposit 50 tokens into the vault"*
   → preflight, `approve` the vault, call `deposit`, read share balance; then *"withdraw"*.
4. **`pharos-allowance-guard`**: approve 3 spenders (one unlimited) → `audit` lists and
   flags the unlimited one → `revoke` it → re-audit shows clean.

## 6. MockVault fixture (Skill 2 only)

Minimal ERC4626-style vault, ~40 lines, OpenZeppelin `IERC20`/`ERC20`:
- `deposit(uint256 assets)` — pulls `assets` via `transferFrom`, mints 1:1 shares.
- `withdraw(uint256 shares)` — burns shares, returns assets.
- `balanceOf` (inherited) — share balance.
Emits events on deposit/withdraw with human-readable revert messages. Purpose: a real
on-chain target so the composition play is demoable; explicitly labeled a test fixture.

## 7. Testing / Verification

This is a docs/CLI skill package, not an application, so verification is:
- **(a)** `forge build` — the `MockVault.sol` fixture compiles cleanly.
- **(b)** `scripts/smoke.sh` — runs the full demo flow against Atlantic testnet given a
  funded `$PRIVATE_KEY`; no-ops with a clear message if `$PRIVATE_KEY` is unset (so it
  is safe to run in CI without secrets).
- **(c)** Markdown lint + relative-link check across all `SKILL.md` / `references/*.md`.

The standard 80% unit-coverage target does **not** apply: there is no application
logic to unit-test — the "logic" is command templates an agent executes. Verification
focuses on "does the fixture compile" and "does the documented command flow actually
work on testnet."

## 8. Scope & Sequencing ("submittable first, then pretty")

- **MVP (submittable):** Skill 1 (`pharos-approvals`) + `README.md` + `LICENSE` +
  public repo pushed. Fills the gap; demoable on its own.
- **Then:** Skill 2 (`pharos-defi-play`) + `MockVault.sol` — the headline multi-step demo.
- **Stretch:** Skill 3 (`pharos-allowance-guard`) — ship if time remains; repo
  structure already reserves its slot.

## 9. Out of Scope (YAGNI)

- No bespoke DEX/lending/staking protocol — `MockVault` is the only shipped contract,
  and only as a demo target.
- No off-chain facilitator / HTTP server (rules out the x402 path's moving parts).
- No multi-chain beyond the official `atlantic-testnet` + `mainnet` entries.
- No automated permit (EIP-2612) support in MVP — could be a future reference section.

## 10. Risks

- **Testnet RPC / faucet availability** — demo needs a funded testnet key; smoke script
  degrades gracefully without one.
- **Revert-decode portability** — `cast` revert strings vary; preflight decodes
  best-effort and always falls back to showing raw stderr.
- **Scope creep on Skill 3** — event-log scanning + pagination is the heaviest piece;
  it is explicitly the stretch item and cut first if time runs short.
