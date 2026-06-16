# Approval Operations

Detailed command specs for the ERC20 approval lifecycle on Pharos. All commands read
the `<rpc>` from `assets/networks.json` (`rpcUrl`, default `atlantic-testnet`).

> **The `--rpc-url` parameter MUST be passed explicitly**, or `cast` defaults to
> `localhost:8545` and the connection fails.
>
> **Write operations** (`approve`, `revoke`, `transferFrom`) MUST pass the private key
> explicitly via `--private-key $PRIVATE_KEY`. Complete the **Write Operation
> Pre-checks** in `SKILL.md` first, and **preflight** the write per
> `references/preflight.md`.

## Amount handling (decimals)

ERC20 amounts are in **base units** = `human_amount × 10^decimals`. Always read the
token's decimals first, then convert:

```bash
DECIMALS=$(cast call <token> "decimals()(uint8)" --rpc-url <rpc>)

# Convert a human amount (e.g. 50) to base units:
AMOUNT=$(cast to-unit "50e0" wei)          # only correct when DECIMALS == 18
# Decimal-agnostic (works for any decimals, e.g. 6 for USDC):
AMOUNT=$(python3 -c "print(int(50 * 10**$DECIMALS))")
# or with bc:
AMOUNT=$(echo "50 * 10^$DECIMALS" | bc)
```

For an **unlimited** approval, the amount is `type(uint256).max`:

```bash
AMOUNT=$(cast max-uint)   # 115792089237316195423570985008687907853269984665640564039457584007913129639935
```

---

## approve — grant an allowance

Authorize `spender` to move up to `amount` (base units) of `<token>` from the caller.

**Command Template**

```bash
cast send <token> "approve(address,uint256)" <spender> <amount> \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY
```

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<token>` | address | Yes | ERC20 token contract address |
| `<spender>` | address | Yes | Address being authorized to spend |
| `<amount>` | uint256 | Yes | Allowance in **base units** (see Amount handling) |
| `<rpc>` | string | Yes | RPC URL from `assets/networks.json` |

**Output Parsing**

`cast send` waits for confirmation and prints a receipt:

| Field | Description |
|-------|-------------|
| `status` | `1` = success, `0` = failed |
| `transactionHash` | Approval transaction hash |
| `blockNumber` | Block containing the tx |

After success, confirm the new allowance with an `allowance` read and show the
explorer link: `<explorerUrl>/tx/<transactionHash>`.

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `invalid address` | Bad token/spender | Check both are `0x` + 40 hex |
| `execution reverted` | Token rejected approve | Decode revert (`references/preflight.md`) |
| missing `--private-key` | No key | Pass `--private-key $PRIVATE_KEY` |
| `insufficient funds` | No gas | Show balance, suggest faucet/top-up |

> **Agent Guidelines**
> 1. Complete Write Operation Pre-checks (`SKILL.md`).
> 2. Read `decimals` and convert the human amount to base units.
> 3. **Default to the exact amount.** If the user asks for "unlimited", use
>    `cast max-uint` AND warn that unlimited approvals are a drainer risk.
> 4. Preflight with `cast call` (`references/preflight.md`); if it reverts, stop and
>    report the decoded reason.
> 5. Broadcast, then read back `allowance` to confirm, and print the explorer link.

---

## allowance — read an approval

Read how much `spender` is currently allowed to move on behalf of `owner`. Gas-free.

**Command Template**

```bash
cast call <token> "allowance(address,address)(uint256)" <owner> <spender> \
  --rpc-url <rpc>
```

**Output Parsing**

Returns the allowance in **base units**. Convert back to human units for display:

```bash
RAW=$(cast call <token> "allowance(address,address)(uint256)" <owner> <spender> --rpc-url <rpc>)
DECIMALS=$(cast call <token> "decimals()(uint8)" --rpc-url <rpc>)
python3 -c "print($RAW / 10**$DECIMALS)"
```

If the value equals `cast max-uint`, report it as **"unlimited (⚠️ drainer risk)"**.

> **Agent Guidelines**: Use this to confirm an `approve`/`revoke` took effect, and as
> the read step inside composed plays. No private key needed.

---

## revoke — reset an allowance to zero

Security hygiene: set a spender's allowance back to `0`. This is just `approve` with
amount `0`.

**Command Template**

```bash
cast send <token> "approve(address,uint256)" <spender> 0 \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY
```

> **Agent Guidelines**: Complete Write Operation Pre-checks. Preflight, broadcast,
> then read back `allowance` to confirm it is `0`. Recommend revoking any allowance
> the user no longer actively needs — especially unlimited ones.

---

## transferFrom — spend an allowance

Move `amount` (base units) of `<token>` from `<from>` to `<to>`, using an allowance
the caller already holds. The caller (`$PRIVATE_KEY` address) must have an allowance
from `<from>` ≥ `amount`.

**Command Template**

```bash
cast send <token> "transferFrom(address,address,uint256)" <from> <to> <amount> \
  --rpc-url <rpc> \
  --private-key $PRIVATE_KEY
```

**Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<from>` | address | Yes | Token owner the allowance is drawn from |
| `<to>` | address | Yes | Recipient |
| `<amount>` | uint256 | Yes | Amount in base units; must be ≤ current allowance |

**Error Handling**

| Error Signature | Cause | Suggested Action |
|---|---|---|
| `execution reverted: ERC20: insufficient allowance` | Allowance too low | Read `allowance` first; approve more or reduce amount |
| `execution reverted: ERC20: transfer amount exceeds balance` | `<from>` lacks tokens | Check `<from>` balance |
| missing `--private-key` | No key | Pass `--private-key $PRIVATE_KEY` |

> **Agent Guidelines**: This is the "agent moves tokens on the user's behalf"
> primitive (delegated transfers, pull-payments, pulling funds into a protocol).
> 1. Pre-checks + read current `allowance(from, caller)` and confirm it covers `amount`.
> 2. Preflight, broadcast, show the explorer link.
