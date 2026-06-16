# Pharos Agent Action Kit

**The agent layer that handles token approvals safely and runs multi-step DeFi plays on Pharos.**

A suite of three composable [Agent Skills](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
that layer on top of the official
[`PharosNetwork/pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine)
and fill its biggest gap: **there is no ERC20 approval layer**. The official engine
can read, transfer, deploy, and airdrop — but it cannot `approve`, read an
`allowance`, `revoke`, or `transferFrom`. Without those, *no* DeFi action (swap,
stake, deposit) can take its first step. This kit adds that keystone primitive and
the safe, multi-step plays built on it.

> Built for the **Pharos Phase 1** hackathon (DoraHacks). Targets the Atlantic
> testnet by default; mainnet is opt-in with explicit warnings.

---

## What's in the kit

| Skill | One-liner | Role |
|-------|-----------|------|
| [`pharos-approvals`](./pharos-approvals) | ERC20 approval lifecycle — `approve` / `allowance` / `revoke` / `transferFrom`, each pre-flighted with a `cast call` dry-run + revert decode before broadcast. | **Keystone** — the missing primitive |
| [`pharos-defi-play`](./pharos-defi-play) | Composed multi-step plays — a generic *approve-then-call* executor, demonstrated by a worked "approve → deposit → check shares → withdraw" vault play. | **The common play** |
| [`pharos-allowance-guard`](./pharos-allowance-guard) | Approval security auditor — scan `Approval` events, resolve live allowances, flag unlimited/risky ones, batch-revoke. | **Wallet hygiene** |

Each skill is **self-contained** (its own `SKILL.md`, `references/`, and
`assets/networks.json`) and follows the official engine's exact format, so an agent
can load any one independently or all three together.

### Why a suite, not one skill

The gap isn't a single command — it's a whole missing *layer*. `pharos-approvals`
grants allowances safely; `pharos-defi-play` spends them in real multi-step actions;
`pharos-allowance-guard` audits and cleans them up. Together they cover the full
approval lifecycle an autonomous agent needs to operate — and survive — on-chain.

---

## How it works

The skills are **knowledge packages for an AI agent** (e.g. Claude Code), not an SDK.
Each `SKILL.md` exposes a **Capability Index** mapping a user's natural-language intent
to a reference file containing exact `cast` / `forge` command templates, parameter
tables, output parsing, and error handling. The agent reads the relevant reference and
runs the commands.

Two design rules tie the suite together and make it safe for autonomous use:

1. **Preflight every write.** Before any `cast send`, the agent simulates the exact
   same calldata with `cast call` and decodes any revert. A write that *would* fail is
   caught for free — no wasted gas, and no half-finished multi-step play. See
   [`pharos-approvals/references/preflight.md`](./pharos-approvals/references/preflight.md).
2. **Exact-amount approvals by default.** Unlimited approvals (`type(uint256).max`) are
   the primary wallet-drainer vector, so the kit scopes allowances to what a play
   actually needs and warns whenever "unlimited" is requested.

All three reuse the official engine's write pre-check protocol: private-key check →
derive & confirm sender → confirm network (warn on mainnet) → preflight.

---

## Install

One command installs all three skills into every agent it detects — **Claude Code,
Codex, OpenClaw, Hermes**, and 9 other runtimes (via [`vercel-labs/skills`](https://github.com/vercel-labs/skills)):

```bash
npx skills add 0xLucas0x/pharos-agent-action-kit -g -y
```

Want just one skill? Add `--skill`:

```bash
npx skills add 0xLucas0x/pharos-agent-action-kit --skill pharos-approvals -g -y
```

`-g` installs globally (per user); drop it for a project-local install. Then verify in a
new session:

| Agent | Skills directory | Verify |
|-------|------------------|--------|
| Claude Code | `~/.claude/skills/` | type `/skills` |
| Codex | `~/.codex/skills/` | type `/skills` |
| OpenClaw | `~/.openclaw/skills/` | `openclaw skills list` |
| Hermes | `~/.hermes/skills/` | type `/skills` or `/pharos-approvals` |

<details>
<summary>Manual install (no CLI)</summary>

Clone and copy the skill folders into your agent's skills directory:

```bash
git clone https://github.com/0xLucas0x/pharos-agent-action-kit.git
cp -r pharos-agent-action-kit/pharos-* ~/.claude/skills/   # or ~/.codex, ~/.openclaw, ~/.hermes ...
```

</details>

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`cast` + `forge`) — the skills check for it
  and print install steps if missing.
- `jq` and `python3` — used for network-config reads and decimal math in the templates.
- A funded Pharos **testnet** key in `$PRIVATE_KEY` for write operations and the demo.

---

## Quick start (natural language)

Once installed, just ask your agent. Examples:

- *"On Pharos, approve 0xSpender to spend 100 of my token 0xToken."*
  → `pharos-approvals` (exact-amount approve, pre-flighted).
- *"How much can 0xSpender spend of my 0xToken?"*
  → `pharos-approvals` (allowance read, gas-free).
- *"Approve the vault and deposit 50 tokens, then show my shares."*
  → `pharos-defi-play` (approve-then-call, two pre-flighted steps).
- *"Audit my token approvals for 0xToken and revoke anything unlimited."*
  → `pharos-allowance-guard` (scan → flag → batch revoke → re-audit).

---

## End-to-end demo

A complete, reliable flow on the Atlantic testnet — no third-party protocol required:

1. **Deploy a token** with the official engine's one-click ERC20 → `0xToken`.
2. **Approvals** — `approve` a spender an exact amount → read `allowance` →
   `transferFrom` → confirm on the explorer.
3. **Play** — deploy `MockVault` (shipped fixture) → *"deposit 50 into the vault"*
   (approve → deposit → read shares) → *"withdraw"*.
4. **Guard** — approve 3 spenders (one unlimited) → `audit` flags the unlimited one →
   `revoke` it → re-audit shows clean.

A scripted version is in [`scripts/smoke.sh`](./scripts/smoke.sh). It runs the full
flow when `$PRIVATE_KEY` is set and exits with a friendly message when it isn't (so it
is safe to run anywhere, including CI without secrets):

```bash
export PRIVATE_KEY=<your_testnet_key>
./scripts/smoke.sh
```

### The `MockVault` fixture

[`pharos-defi-play/assets/vault/MockVault.sol`](./pharos-defi-play/assets/vault/MockVault.sol)
is a minimal, self-contained ERC4626-style vault used **only as a demo target** so the
approve-then-call play has something real to act on. It pulls deposits via
`transferFrom` (which is exactly why an approval is required) and mints shares 1:1. It
is a **test fixture** — no yield, no fees — do not use it with real value. Verify it
compiles with:

```bash
forge build
```

---

## Use cases

- **Autonomous DeFi agents** that need to interact with any protocol — every
  swap/stake/deposit starts with an approval the official engine can't do.
- **Agentic payments / pull flows** — `transferFrom` lets an agent move tokens on a
  user's behalf within a scoped allowance.
- **Wallet security agents** — periodically audit and revoke risky approvals, the
  single most effective defense against approval-based drains.
- **A reusable approval layer** other Pharos skills can build on.

---

## Project layout

```text
pharos-agent-action-kit/
├── README.md
├── LICENSE                         # MIT
├── foundry.toml                    # compiles the MockVault fixture
├── scripts/smoke.sh                # end-to-end demo runner (safe without a key)
├── docs/superpowers/specs/         # design spec
├── pharos-approvals/               # Skill 1 — keystone
│   ├── SKILL.md
│   ├── references/{approve,preflight}.md
│   └── assets/networks.json
├── pharos-defi-play/               # Skill 2 — composition
│   ├── SKILL.md
│   ├── references/play.md
│   └── assets/{networks.json, vault/MockVault.sol}
└── pharos-allowance-guard/         # Skill 3 — security
    ├── SKILL.md
    ├── references/audit.md
    └── assets/networks.json
```

---

## Safety notes

- **Testnet by default.** Every skill defaults to `atlantic-testnet`; mainnet requires
  an explicit, re-confirmed request.
- **Keys never logged.** Pass `--private-key $PRIVATE_KEY` explicitly (Foundry does not
  auto-read env vars); the skills never echo key material.
- **Preflight before broadcast** on every write.
- The `MockVault` is a demo fixture, not audited production code.

## License

[MIT](./LICENSE)
