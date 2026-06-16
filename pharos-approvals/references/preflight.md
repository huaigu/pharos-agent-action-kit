# Preflight — Simulate Writes Before Broadcasting

The safety thread tying this suite together: **before any `cast send`, simulate the
exact same call with `cast call`** and decode any revert. A simulated call executes
the contract logic against current chain state without broadcasting a transaction or
spending gas — so a write that *would* revert is caught **before** it costs anything
or, worse, half-completes a multi-step play.

## Why

`cast send` broadcasts immediately. If the call reverts, the user still pays gas for
the failed transaction and — in a composed play — may be left in a partial state
(e.g. approved but the deposit failed). `cast call` runs the same calldata in a
read-only EVM context and returns the revert data instead.

## Pattern

For any write `cast send <to> "<sig>" <args...> --private-key $PRIVATE_KEY`, the
preflight is the **same call** with `cast call` and `--from` set to the sender:

```bash
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)

# Preflight (read-only simulation, no gas, no broadcast):
cast call <to> "<sig>" <args...> --from "$SENDER" --rpc-url <rpc>
```

- **Exit code 0 / clean return** → the write is expected to succeed. Proceed to
  `cast send`.
- **Reverts** → `cast call` prints the revert. STOP, decode it (below), and report a
  human-readable reason to the user. Do NOT broadcast.

### Example: preflight an approve

```bash
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
cast call <token> "approve(address,uint256)" <spender> <amount> --from "$SENDER" --rpc-url <rpc> \
  && echo "preflight OK — safe to send" \
  || echo "preflight reverted — see reason above, NOT broadcasting"
```

### Example: preflight a transferFrom

```bash
SENDER=$(cast wallet address --private-key $PRIVATE_KEY)
cast call <token> "transferFrom(address,address,uint256)" <from> <to> <amount> --from "$SENDER" --rpc-url <rpc>
```

If `<from>` has not approved `SENDER`, this reverts with
`ERC20: insufficient allowance` — caught here, for free.

## Decoding revert reasons

`cast call` usually surfaces the reason directly, e.g.
`execution reverted: ERC20: insufficient allowance`. When you only get raw revert
bytes (a custom error or a `Panic`), decode them:

```bash
# Decode a 4-byte custom-error selector or full error data:
cast decode-error <0x-revert-data>

# Look up an unknown 4-byte selector in the signature database:
cast 4byte <0xselector>

# Decode a Solidity Error(string) payload manually if needed:
cast abi-decode "Error(string)" <0x-revert-data>
```

Always fall back to showing the **raw stderr** if decoding fails — never swallow the
error.

## Gas estimate (optional companion)

Once preflight passes, you may also surface the cost:

```bash
cast estimate <to> "<sig>" <args...> --from "$SENDER" --rpc-url <rpc>
```

> **Agent Guidelines**: Preflight is **mandatory** before every write in this suite
> (`approve`, `revoke`, `transferFrom`, and every step of a composed play). The rule:
> *simulate → decode on revert → only then broadcast.* In a multi-step play, preflight
> the **next** step against the state produced by the previous one, so the play aborts
> cleanly instead of stranding the user mid-sequence.
