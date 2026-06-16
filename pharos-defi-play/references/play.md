# DeFi Plays — Composed Multi-Step Sequences

A **play** is a guarded sequence of primitives executed as one user intent. Every step
follows the suite rule: **preflight (simulate) → decode on revert → broadcast**, and
each step is preflighted against the chain state left by the previous step, so the
play aborts cleanly rather than stranding the user mid-sequence.

All commands read `<rpc>` from `assets/networks.json` (default `atlantic-testnet`) and
pass writes with `--private-key $PRIVATE_KEY`. See `pharos-approvals/references/approve.md`
for amount/decimals handling and `pharos-approvals/references/preflight.md` for the
simulation + revert-decode details this skill depends on.

---

## approve-then-call (generic)

The universal DeFi building block: grant an allowance to a target contract, then call
the method that pulls those tokens (`deposit`, `stake`, `supply`, `swap`, ...).

**Inputs:** `<token>`, `<target>` (the contract that will pull the tokens),
`<amount>` (human units), `<method>` (e.g. `deposit(uint256)`), and the method args.

**Sequence**

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
DECIMALS=$(cast call <token> "decimals()(uint8)" --rpc-url "$RPC")
AMOUNT=$(python3 -c "print(int(<human_amount> * 10**$DECIMALS))")

# --- Step 1: APPROVE the target for exactly the play amount ---
# 1a. preflight
cast call <token> "approve(address,uint256)" <target> "$AMOUNT" --from "$SENDER" --rpc-url "$RPC"
# 1b. broadcast
cast send <token> "approve(address,uint256)" <target> "$AMOUNT" --rpc-url "$RPC" --private-key $PRIVATE_KEY
# 1c. confirm
cast call <token> "allowance(address,address)(uint256)" "$SENDER" <target> --rpc-url "$RPC"

# --- Step 2: CALL the target method (now that the allowance exists) ---
# 2a. preflight against post-approval state
cast call <target> "<method>" <args...> --from "$SENDER" --rpc-url "$RPC"
# 2b. broadcast
cast send <target> "<method>" <args...> --rpc-url "$RPC" --private-key $PRIVATE_KEY
```

> **Agent Guidelines**
> 1. Run Write Operation Pre-checks once at the start.
> 2. Compute `AMOUNT` from the token's real `decimals`.
> 3. Approve the **exact** play amount (not unlimited) unless the user insists.
> 4. **If Step 2's preflight reverts, do NOT broadcast it** — report the decoded
>    reason. Tell the user they have an outstanding allowance from Step 1 and offer to
>    `revoke` it (`pharos-approvals` → revoke) so they are not left exposed.
> 5. On success, read back the resulting state (shares/staked balance) and print
>    explorer links for both transactions.

---

## Deploy the MockVault demo target

`assets/vault/MockVault.sol` is a minimal, self-contained ERC4626-style vault used
purely as a **demo target** so the play above has something real to act on. It pulls
deposits via `transferFrom` (which is exactly why the approval step is required) and
mints shares 1:1. It is a test fixture — no yield, no fees — do not use with real value.

**Deploy (constructor takes the asset token address):**

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)

forge create pharos-defi-play/assets/vault/MockVault.sol:MockVault \
  --rpc-url "$RPC" \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args <asset_token_address>
```

`forge create` prints `Deployed to: <vault_address>` — capture it as `<target>` for
the play. (If `forge create` is unavailable, fall back to the official engine's
`forge script` deploy flow.)

---

## Vault deposit (worked play)

Concrete instantiation of approve-then-call with `MockVault.deposit`.

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
DECIMALS=$(cast call <token> "decimals()(uint8)" --rpc-url "$RPC")
AMOUNT=$(python3 -c "print(int(50 * 10**$DECIMALS))")   # deposit 50 tokens

# Step 1 — approve the vault for 50 tokens
cast call <token> "approve(address,uint256)" <vault> "$AMOUNT" --from "$SENDER" --rpc-url "$RPC"
cast send <token> "approve(address,uint256)" <vault> "$AMOUNT" --rpc-url "$RPC" --private-key $PRIVATE_KEY

# Step 2 — deposit (pulls the 50 tokens via transferFrom, mints 50 shares)
cast call <vault> "deposit(uint256)" "$AMOUNT" --from "$SENDER" --rpc-url "$RPC"
cast send <vault> "deposit(uint256)" "$AMOUNT" --rpc-url "$RPC" --private-key $PRIVATE_KEY

# Confirm — share balance should now be 50 * 10^decimals
cast call <vault> "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC"
```

**Output Parsing**

| Read | Meaning |
|------|---------|
| `allowance(SENDER, vault)` after Step 1 | should equal `AMOUNT` |
| `balanceOf(SENDER)` on the vault after Step 2 | minted shares (== deposited assets, 1:1) |
| `Deposit(user, assets, shares)` event | emitted on success |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `MockVault: transferFrom failed (check allowance)` | Step 1 missing/too small | Re-run Step 1 with ≥ deposit amount |
| `MockVault: deposit amount must be > 0` | Zero amount | Use a positive amount |
| `execution reverted` on Step 2 preflight | Allowance/balance issue | Decode (`preflight.md`); do not broadcast; offer to revoke the Step-1 allowance |

---

## Vault withdraw

Single write (no approval needed — the user already holds the shares).

```bash
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
SHARES=$(python3 -c "print(int(50 * 10**$(cast call <token> 'decimals()(uint8)' --rpc-url "$RPC")))")

# preflight then withdraw
cast call <vault> "withdraw(uint256)" "$SHARES" --from "$SENDER" --rpc-url "$RPC"
cast send <vault> "withdraw(uint256)" "$SHARES" --rpc-url "$RPC" --private-key $PRIVATE_KEY

# Confirm — vault share balance should drop back to 0 and token balance return
cast call <vault> "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC"
cast call <token> "balanceOf(address)(uint256)" "$SENDER" --rpc-url "$RPC"
```

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `MockVault: insufficient shares` | Withdrawing more than held | Read `balanceOf` on the vault first |
| `MockVault: withdraw amount must be > 0` | Zero amount | Use a positive amount |

> **Agent Guidelines**: The full demo is deploy ERC20 (official engine) → deploy
> MockVault → deposit play → withdraw. Always preflight; on any mid-play revert, stop
> and surface the decoded reason plus the user's current allowance/share state.
