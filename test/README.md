# Pegzeus test coverage

The original `Pegzeus.t.sol` remains unchanged. The additional suites are:

- `PegzeusProperties.t.sol`: unit tests for one base unit, the entire supply,
  `uint256.max`, finite versus infinite approvals, self-transfers, revocation,
  and recovery after rejected spending. Seven fuzz properties exercise exact
  round trips, split transfers, independent approvals, and failure atomicity,
  with 1,000 runs each.
- `PegzeusInvariant.t.sol`: three invariants checked after every handler call,
  over 256 runs of 128 calls. They enforce the specified supply and metadata,
  conservation and each holder's balance, and every actor-pair allowance.
  The deterministic handler test also reaches successful nonzero operations
  and each family of rejected operations.

The handler deploys the real token and distributes its constructor allocation
among four actors, including the immediate deployer. It selects transfers,
approvals (including replacement and revocation), delegated transfers, invalid
recipients/spenders, overspending, and unavailable administrative calls in random
order. Self-transfers and transfers to the token contract are included. The token
is a passive recipient, never impersonated as a sender.

The accounting oracle uses cumulative authorized credits/debits and recorded
owner approvals, not balances copied back from the implementation. All reachable
recipients are tracked. Failed calls must return the expected error and leave
the ledger and authorizations unchanged; the next invariant check verifies the
actual state against them. `fail-on-revert = true` prevents a failed handler
assertion from being discarded. The fuzzer targets only the eight handler
actions, so it cannot bypass the accounting oracle.

Run from the repository root with the assignment's seed:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x6d5918f92fd2713891527bc18aff1dbfc53ac4c242542b23e5218d686c4a3593 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The output overrides keep generated build artifacts in scratch space. They are
optional for normal `forge build` / `forge test`. Run counts are inline in the
Solidity tests. The small local cheatcode interface and Foundry targeting ABI
require no additional dependencies, configuration changes, RPC, or environment
mutation.
