# Allowance Audit & Batch Revoke

Find every spender a user has approved for an ERC20 token, resolve each spender's
**live** allowance, flag the risky ones, and batch-revoke the user's choices. Reads
are gas-free; the revoke step reuses the `pharos-approvals` revoke flow.

All commands read `<rpc>` from `assets/networks.json` (default `atlantic-testnet`).

---

## audit — list spenders

ERC20 emits `Approval(address indexed owner, address indexed spender, uint256 value)`
on every `approve`. Scan those logs for the owner, collect the **distinct spenders**,
then query each one's **current** allowance (events are history; the live allowance is
truth).

**Step 1 — fetch Approval logs for the owner**

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
OWNER=<owner_address>          # often: cast wallet address --private-key $PRIVATE_KEY
TOKEN=<token_address>

# owner is the first indexed topic; pass it to filter, spender left as wildcard
cast logs \
  "Approval(address indexed owner, address indexed spender, uint256 value)" \
  "$OWNER" \
  --address "$TOKEN" \
  --from-block 0 --to-block latest \
  --rpc-url "$RPC"
```

**Step 2 — extract distinct spenders**

Each log's `topics[2]` is the indexed spender (left-padded to 32 bytes). Convert to a
checksummed address and dedupe:

```bash
# From a 32-byte topic to a 20-byte address:
cast parse-bytes32-address <topic2>
```

> On a busy network, narrow `--from-block` to a recent window (or the token's deploy
> block) to bound the scan. If you cap the range, **say so explicitly** — report the
> block window scanned so the user knows the audit is not necessarily exhaustive.

**Step 3 — resolve the live allowance per spender**

```bash
for SPENDER in <spender1> <spender2> ...; do
  RAW=$(cast call "$TOKEN" "allowance(address,address)(uint256)" "$OWNER" "$SPENDER" --rpc-url "$RPC")
  echo "$SPENDER -> $RAW"
done
```

Spenders whose live allowance is `0` are already clean (a past approval was revoked or
fully spent) — list them as "clear", focus the user on the non-zero ones.

> **Agent Guidelines**: Build a table of `spender | live allowance (human) | risk`.
> Resolve `decimals` once (`cast call <token> "decimals()(uint8)"`) to render human
> amounts. Never rely on event `value` for the current state — always re-read
> `allowance`.

---

## flag — classify risk

Classify each non-zero live allowance:

| Live allowance | Risk | Label |
|---|---|---|
| `== cast max-uint` (`2^256-1`) | High | **UNLIMITED ⚠️ — recommend revoke** |
| Large relative to the user's balance (e.g. ≥ balance) | Medium | Review — covers your whole balance |
| Small, scoped to a known spender | Low | Likely intentional |
| `0` | None | Clear (nothing to do) |

```bash
MAX=$(cast max-uint)
if [ "$RAW" = "$MAX" ]; then echo "UNLIMITED (high risk)"; fi
```

> **Agent Guidelines**: Always single out unlimited approvals first. For medium-risk
> ones, show the allowance next to the user's current token balance
> (`cast call <token> "balanceOf(address)(uint256)" <owner>`) so "this spender can move
> everything you hold" is concrete. Recommend, but let the user decide.

---

## batch-revoke

Revoke is `approve(spender, 0)`. Apply it to the spenders the user selects. Each one is
a write — preflight then broadcast (see `pharos-approvals/references/preflight.md`).

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
TOKEN=<token_address>

for SPENDER in <selected_spenders...>; do
  # preflight
  cast call "$TOKEN" "approve(address,uint256)" "$SPENDER" 0 \
    --from "$(cast wallet address --private-key $PRIVATE_KEY)" --rpc-url "$RPC" || { echo "preflight failed for $SPENDER, skipping"; continue; }
  # broadcast
  cast send "$TOKEN" "approve(address,uint256)" "$SPENDER" 0 \
    --rpc-url "$RPC" --private-key $PRIVATE_KEY
done
```

**Confirm** — re-run the `audit` afterward; every revoked spender should now read `0`.

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| missing `--private-key` | No key | Pass `--private-key $PRIVATE_KEY` |
| `insufficient funds` | No gas for the revokes | Show balance; revoke fewer / top up |
| `nonce too low` | Concurrent txs | Let one confirm before the next, or set `--nonce` |

> **Agent Guidelines**: List the spenders to be revoked and get explicit user
> confirmation before broadcasting (it is a batch of state-changing txs). Revoke
> sequentially so nonces stay ordered. After the batch, re-audit and present the clean
> state with explorer links for each revoke tx.
