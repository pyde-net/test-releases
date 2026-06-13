<h1 align="center">pyde-net / test-releases</h1>

<p align="center">
  <em>Public release mirror for the Pyde Network toolchain</em>
</p>

---

This repository holds **only the signed release artifacts** for Pyde Network's developer toolchain — no source code. Source code lives in the individual product repos and stays private during pre-mainnet engineering.

Use this mirror when you want to **install a Pyde tool, not read its code**. Everything here is meant to be downloaded by the per-product `install.sh` script over plain `curl`.

## What's here

```
otigen/install.sh           # canonical install script for otigen
engine/install.sh           # (future) install script for the pyde validator binary
```

## Installing otigen

```bash
curl -fsSL https://raw.githubusercontent.com/pyde-net/test-releases/main/otigen/install.sh | bash
exec $SHELL -l                          # reload PATH
otigen --version
```

The install script probes this mirror anonymously, picks the right platform binary, verifies sha256, drops the binary into `~/.otigen/bin/`, and adds it to your `PATH`. No `gh` install, no `GITHUB_TOKEN` setup, no auth dance.

Sigstore signatures (cosign) are uploaded alongside every release for users who want full keyless provenance verification — see [Verifying a download manually](#verifying-a-download-manually) below.

## Tag convention

Releases use a `<product>-<version>` tag prefix so the mirror can host every Pyde toolchain release under one timeline:

| Tag pattern              | Product               |
|--------------------------|-----------------------|
| `otigen-vX.Y.Z`          | The otigen developer CLI |
| `engine-vX.Y.Z`          | The pyde validator binary (future) |

Each tag carries: signed platform tarballs (Linux x86_64 + aarch64, macOS arm64, Windows x86_64), sha256 manifests, sigstore cosign signatures + certificates. Pre-releases use a hyphenated suffix (`-alpha`, `-testnet.1`, `-rc1`); stable tags are bare `vX.Y.Z`.

## Learn more

Once `otigen` is on your `PATH`, these are the canonical entry points for everything you'd want — quick-start tour, behaviour-test framework, host-fn ABI, and the community SDK contribution path.

### Quick reference — start here

- [Chapter 5 — Otigen Toolchain](https://book.pyde.network/chapters/05-otigen-toolchain.html) — narrative tour of every subcommand with examples (`init` → `build` → `test` → `deploy` → `inspect` → `verify` → `console`).
- [Chapter 5 §5.9 — The Console](https://book.pyde.network/chapters/05-otigen-toolchain.html#59-the-console) — `otigen console` REPL: live `state` / `events` / `call` / `tx` against any Pyde node.

### Canonical specifications

These are the authoritative specs the binary implements. If the implementation and the spec disagree, the spec is right and the code is a bug.

- [`OTIGEN_BINARY_SPEC`](https://book.pyde.network/companion/OTIGEN_BINARY_SPEC.html) — every subcommand, flag, schema rule, exit code.
- [`OTIGEN_TEST_SPEC`](https://book.pyde.network/companion/OTIGEN_TEST_SPEC.html) — full Foundry-shape behaviour-test spec: cheats, FALCON DSL, expectations, mocking model.
- [`HOST_FN_ABI_SPEC`](https://book.pyde.network/companion/HOST_FN_ABI_SPEC.html) — the chain-facing WASM ABI the toolchain validates against (every host fn, gas table, error codes, versioning rules).
- [`WASM_AUTHOR_GUIDE`](https://book.pyde.network/companion/WASM_AUTHOR_GUIDE.html) — pattern guide for contract authors: storage, FALCON in-contract, cross-call, proxy, merkle, composition.

### Canonical contract examples

The otigen source repo (currently private during pre-mainnet) ships ~30 canonical example contracts — counter / counter-token ports across Rust, TinyGo, AssemblyScript, and C; ERC20 + ERC721 tokens; upgradeable proxy; Uniswap V2-style AMM; DAO governance; payment channel; FALCON-signed multisig; merkle-tree airdrop; vesting; storage-stress acceptance suite. Each boots to a passing `otigen test` suite and a live `make e2e` run against `otigen devnet`. They'll be browsable here once the source repo flips public.

### Contributing a community SDK (Go / TypeScript / Zig / …)

Pyde Network ships **one canonical contract-side SDK** — the Rust stack (`pyde-host`, `pyde-storage-macros`, `pyde-events-macros`, `pyde-entry-macros`). Bringing any other language to Pyde is a community pathway: the chain holds a stable WASM ABI and a stable bundle format, and everything above is open to any language that targets `wasm32-unknown-unknown`.

The contract a community SDK must satisfy:

- [**`SDK_AUTHOR_GUIDE`**](https://book.pyde.network/companion/SDK_AUTHOR_GUIDE.html) — the four invariants every SDK must hold (`() -> ()` entry signature, borsh-canonical calldata, host-fn signature parity, `pyde.abi` custom section), the reference implementation's surface, and the quality bar to ship.
- [Chapter 17 §17.3 — Contract-side SDKs (community)](https://book.pyde.network/chapters/17-developer-tools.html#contract-side-sdks-community) — the discoverable entry point in the book. Lists community SDKs as they ship.

The canonical acceptance contract for community SDKs is `examples/storage-stress` in the otigen repo: a community SDK is "ready" when its port of the 28-assertion `tests/stress_e2e.py` passes end-to-end against `pyde devnet`. Browse it here once the otigen source repo flips public.

Community SDKs publish under their own org (e.g., `pyde-go/`, `pyde-ts-contracts/`) and are listed back into the book by PR against the book repo.

#### What the Rust SDK looks like (reference shape)

To anchor what your SDK is porting, here's the canonical minimal-counter contract in the Rust SDK end-to-end. Your SDK's macros / decorators / proc-gen need to emit the equivalent shape from your language's syntax.

**`otigen.toml`** — the source of truth for state schema and function signatures. SDKs read this at compile time to generate typed accessors + the `pyde.abi` custom section.

```toml
[contract]
name    = "counter-rust"
version = "0.1.0"
type    = "contract"

[contract.lang]
language = "rust"
output   = "target/wasm32-unknown-unknown/release/counter_rust.wasm"

[state]
schema = [
    { name = "counter", type = "uint64" },
]

[functions.increment]
attributes = ["entry"]
inputs     = []
outputs    = ["int64"]

[functions.get]
attributes = ["entry", "view"]
inputs     = []
outputs    = ["int64"]
```

**`src/lib.rs`** — the contract body. Three macros do the heavy lifting:

```rust
#![no_std]
extern crate alloc;

use core::panic::PanicInfo;
use pyde_host as pyde;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

// `declare_storage!()` reads `otigen.toml`'s [state].schema at compile
// time and emits one typed accessor per field. Misspelling a field
// name or supplying the wrong value type is a compile error.
pyde::declare_storage!();

// `#[pyde::entry]` wraps each function in the `() -> ()` shim Pyde
// requires at the WASM boundary: decode calldata → call this inner
// body → borsh-encode the return value → surface it via `pyde::return`.
#[pyde::entry]
fn increment() -> u64 {
    let next = storage::counter().read().wrapping_add(1);
    storage::counter().write(next);
    next
}

#[pyde::entry]
fn get() -> u64 {
    storage::counter().read()
}
```

What an SDK port must produce for the equivalent WASM module:
- **Every exported function** has WASM type `() -> ()`. Args flow in via `pyde::calldata_size` + `pyde::calldata_copy`; return values flow out via `pyde::return`. The chain's deploy validator rejects any other shape.
- **Storage accessors** read the same `[state].schema` and emit typed read/write/delete operations that route through the chain's typed-storage host fns (`sstore_scalar` / `sload_scalar` / `sstore_map<N>` / `sload_map<N>`), so slot derivation stays on the chain side (`Poseidon2(self_address ‖ field_name ‖ keys…)`).
- **The `pyde.abi` custom section** is borsh-encoded from `otigen.toml`'s `[contract]` + `[state]` + `[functions]` + `[events]` + `[types]` tables and injected into the WASM module after compilation. The chain reads it at deploy time for function lookup, attribute enforcement, and ABI compatibility checks.
- **Calldata + return values** are canonical borsh-encoded per the type tokens declared in `otigen.toml`. Same wire format the Rust SDK + the test framework agree on.

The four bullets above are the [`SDK_AUTHOR_GUIDE`](https://book.pyde.network/companion/SDK_AUTHOR_GUIDE.html) invariants in one paragraph — read the spec for the full normative version (every host fn, gas cost, error code, attribute, edge case).

## Verifying a download manually

If you want to validate a release artifact outside the install script:

```bash
# Pick the right artifact name for your platform
ARTIFACT="otigen-v0.1.0-alpha.1-aarch64-apple-darwin.tar.gz"

# Download artifact + sha256 + sigstore signature + certificate
gh release download otigen-v0.1.0-alpha.1 --repo pyde-net/test-releases \
  --pattern "$ARTIFACT" \
  --pattern "$ARTIFACT.sha256" \
  --pattern "$ARTIFACT.sig" \
  --pattern "$ARTIFACT.pem"

# Verify sha256
shasum -a 256 -c "$ARTIFACT.sha256"

# Verify sigstore (keyless OIDC; cert pins the workflow run that signed)
cosign verify-blob \
  --signature "$ARTIFACT.sig" \
  --certificate "$ARTIFACT.pem" \
  --certificate-identity-regexp "https://github.com/pyde-net/otigen" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$ARTIFACT"
```

The `--certificate-identity-regexp` matches the OIDC subject embedded in the cosign cert by the GitHub Actions workflow that built the artifact — verifying the binary was signed by a workflow run on `pyde-net/otigen`. The regexp doesn't fetch anything from GitHub; cosign reads the subject out of the certificate locally.

## Where the canonical surfaces live

| Surface                                  | URL                                                                 |
|------------------------------------------|---------------------------------------------------------------------|
| Pyde Network                             | <https://pyde.network>                                              |
| Protocol book + companion specs (live)   | <https://book.pyde.network>                                         |
| Release mirror (you are here)            | <https://github.com/pyde-net/test-releases>                         |

Source repos (`pyde-net/otigen`, `pyde-net/engine`, `pyde-net/pyde-book`, `pyde-net/pips`) stay private during pre-mainnet engineering and will be linked from here as they flip public.

This repo accepts no PRs against its contents — every file is generated by the upstream release workflows.

## License

The release artifacts here are licensed per their source repo (Apache-2.0 for otigen).
