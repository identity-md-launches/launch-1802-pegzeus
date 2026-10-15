# Pegzeus (PEGZ)

Pegzeus is a fixed-supply ERC-20 built with Solidity 0.8.26 and the vendored,
unmodified ERC-20 subset of OpenZeppelin Contracts v5.0.2 (MIT).

| Parameter | Value |
| --- | --- |
| Contract | `src/Pegzeus.sol:Pegzeus` |
| Name | Pegzeus |
| Symbol | PEGZ |
| Decimals | 18 |
| Supply | 1,000,000,000 PEGZ |
| Supply in base units | `1000000000000000000000000000` (`10**27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |

The constructor mints the entire supply once and emits
`Transfer(address(0), deployer, supply)`. Deployment through a factory credits
the factory, which is responsible for subsequent distribution. The external
caller of that factory receives no constructor allocation directly.

## Behavior and assumptions

The brief is interpreted as a standard ERC-20 with exact transfers, no taxes,
no rebasing, and no additional application contracts. There is no owner,
administrative role, external mint or burn function, pause, blacklist, proxy,
or upgrade mechanism. The supply remains fixed for the lifetime of this contract.
Token operations make no external calls and use no oracles or chain-specific
addresses. The deployable bytecode requires no linked libraries.

`transfer`, `approve`, and `transferFrom` return true on success and revert on
failure using OpenZeppelin's ERC-6093 custom errors. Transfers to the zero
address and approvals to a zero spender revert. Zero-value transfers and
self-transfers are supported. Ordinary transfers emit `Transfer`; approvals
emit `Approval`. Finite allowances decrease when spent; the maximum uint256
allowance remains unchanged. This OpenZeppelin implementation does not emit
an additional `Approval` event when `transferFrom` spends an allowance.

## Build and verification

Install Foundry with Solidity 0.8.26 available, then run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6d5918f92fd2713891527bc18aff1dbfc53ac4c242542b23e5218d686c4a3593 forge test
forge fmt --check
```

All Solidity dependencies are ordinary files under `lib/`; builds need no
dependency downloads. `foundry.toml` pins Solidity 0.8.26, the Cancun EVM target,
optimizer settings (200 runs), and `bytecode_hash = "none"`. Fuzz tests run
1,000 cases each. Tests do not read or modify environment variables, fork a
chain, or require RPC credentials.

The tests cover metadata, deployment by a factory, mint and transfer events,
exact transfers, allowance replacement/revocation, finite and infinite
allowances, rejected unauthorized actions, invalid recipients, insufficient
balances/allowances, rollback on failure, and fuzzed conservation across
sequences of transfers and delegated transfers.

## Deployment and operations

The intended launch chain is Ethereum (chain ID 1). Deploy the compiled
`Pegzeus` creation bytecode directly through the launch factory with no
constructor arguments or initialization call. The factory receives all
`10**27` base units and handles distribution and pool setup under the launch
policy; the token itself performs neither operation. No launch manifest or
transactions are produced by this project.

After launch, the deployment operator should verify the published address,
source/compiler settings, metadata, total supply, constructor mint event, and
factory distribution. There are no owner-settable settings or maintenance
transactions. Holders control transfers and allowances; integrations should
query current allowances and holders should approve only trusted spenders,
prefer exact allowances, and revoke obsolete approvals. When changing an
existing allowance, setting it to zero first helps address the standard ERC-20
approval ordering risk.

There is no recovery mechanism for assets sent to this token contract or an
incorrect recipient. The operator remains responsible for source verification
and independent security review before release. Local validation uses Foundry
unit and fuzz tests plus code review against the supplied security reference;
Slither and Mythril were not run. These checks are not an independent audit.
