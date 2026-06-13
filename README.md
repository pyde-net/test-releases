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

For the full subcommand surface, see [`pyde-net/otigen`](https://github.com/pyde-net/otigen) — that's where the source, docs, and examples live. The next section is a curated entry point to everything you'd want once the binary is installed.

## Learn more

### Quick reference — start here

- [`pyde-net/otigen/README.md`](https://github.com/pyde-net/otigen#readme) — full subcommand table, quick-start walk-through, testing framework cheat sheet.
- [Chapter 5 — Otigen Toolchain](https://github.com/pyde-net/pyde-book/blob/main/src/chapters/05-otigen-toolchain.md) — narrative tour of every subcommand with examples (`init` → `build` → `test` → `deploy` → `inspect` → `verify` → `console`).
- [Chapter 5 §5.9 — The Console](https://github.com/pyde-net/pyde-book/blob/main/src/chapters/05-otigen-toolchain.md#59-the-console) — `otigen console` REPL: live `state` / `events` / `call` / `tx` against any Pyde node.

### Canonical specifications

These are the authoritative specs the binary implements. If the implementation and the spec disagree, the spec is right and the code is a bug.

- [`OTIGEN_BINARY_SPEC.md`](https://github.com/pyde-net/pyde-book/blob/main/src/companion/OTIGEN_BINARY_SPEC.md) — every subcommand, flag, schema rule, exit code.
- [`OTIGEN_TEST_SPEC.md`](https://github.com/pyde-net/pyde-book/blob/main/src/companion/OTIGEN_TEST_SPEC.md) — full Foundry-shape behaviour-test spec: cheats, FALCON DSL, expectations, mocking model.
- [`HOST_FN_ABI_SPEC.md`](https://github.com/pyde-net/pyde-book/blob/main/src/companion/HOST_FN_ABI_SPEC.md) — the chain-facing WASM ABI the toolchain validates against (every host fn, gas table, error codes, versioning rules).
- [`WASM_AUTHOR_GUIDE.md`](https://github.com/pyde-net/pyde-book/blob/main/src/companion/WASM_AUTHOR_GUIDE.md) — pattern guide for contract authors: storage, FALCON in-contract, cross-call, proxy, merkle, composition.

### Canonical contract examples

Every example below boots to a passing `otigen test` suite + a live `make e2e` run against `otigen devnet`. Read them as a how-to for the patterns Pyde supports today.

- [`examples/`](https://github.com/pyde-net/otigen/tree/main/examples) — full catalogue (~30 contracts) in the otigen repo.
- [`counter-rust`](https://github.com/pyde-net/otigen/tree/main/examples/counter-rust) — minimal Pyde contract via the Rust macro substrate (`#[pyde::entry]` + `declare_storage!()` + `declare_events!()`).
- [`erc20-token`](https://github.com/pyde-net/otigen/tree/main/examples/erc20-token) — ERC20-style fungible token: substrate-typed storage + indexed events + composite-key mapping.
- [`erc721-token`](https://github.com/pyde-net/otigen/tree/main/examples/erc721-token) — ERC721 NFT: per-token ownership + `setApprovalForAll` + `transferFrom`.
- [`upgradeable-proxy`](https://github.com/pyde-net/otigen/tree/main/examples/upgradeable-proxy) — admin-gated proxy via `execute_delegate_raw`. Survives v1 → v2 upgrades end-to-end.
- [`amm-uniswap-v2`](https://github.com/pyde-net/otigen/tree/main/examples/amm-uniswap-v2) — constant-product AMM, Uniswap V2 math. Cross-contract calls into ERC20 sides.
- [`dao-governance`](https://github.com/pyde-net/otigen/tree/main/examples/dao-governance) — full proposal lifecycle: propose → vote → execute, with cross-contract execution.
- [`payment-channel`](https://github.com/pyde-net/otigen/tree/main/examples/payment-channel) — off-chain signed claims via `falcon_verify`, on-chain settlement via `delegate_call`.
- [`multisig-wallet`](https://github.com/pyde-net/otigen/tree/main/examples/multisig-wallet) — M-of-N FALCON-signed multisig with value-forwarding cross-calls and replay protection.

Alternative-language ports (TinyGo / AssemblyScript / C) of `counter` and `counter-token` live alongside the Rust references — same surface, same behaviour, different SDK shape.

### Contributing a community SDK (Go / TypeScript / Zig / …)

Pyde Network ships **one canonical contract-side SDK** — the Rust stack in `pyde-net/otigen` (`pyde-host`, `pyde-storage-macros`, `pyde-events-macros`, `pyde-entry-macros`). Bringing any other language to Pyde is a community pathway: the chain holds a stable WASM ABI and a stable bundle format, and everything above is open to any language that targets `wasm32-unknown-unknown`.

The contract a community SDK must satisfy:

- [**`SDK_AUTHOR_GUIDE.md`**](https://github.com/pyde-net/pyde-book/blob/main/src/companion/SDK_AUTHOR_GUIDE.md) — the four invariants every SDK must hold (`() -> ()` entry signature, borsh-canonical calldata, host-fn signature parity, `pyde.abi` custom section), the reference implementation's surface, and the quality bar to ship.
- [Chapter 17 §17.3 — Contract-side SDKs (community)](https://github.com/pyde-net/pyde-book/blob/main/src/chapters/17-developer-tools.md#contract-side-sdks-community) — the discoverable entry point in the book. Lists community SDKs as they ship.
- [`examples/storage-stress`](https://github.com/pyde-net/otigen/tree/main/examples/storage-stress) — the canonical acceptance contract. A community SDK is "ready" when its port of the 28-assertion `tests/stress_e2e.py` passes end-to-end against `pyde devnet`.

Community SDKs publish under their own org (e.g., `pyde-go/`, `pyde-ts-contracts/`) and are listed back into the book by PR against [`pyde-net/pyde-book`](https://github.com/pyde-net/pyde-book).

## Tag convention

Releases use a `<product>-<version>` tag prefix so the mirror can host every Pyde toolchain release under one timeline:

| Tag pattern              | Product               |
|--------------------------|-----------------------|
| `otigen-vX.Y.Z`          | The otigen developer CLI |
| `engine-vX.Y.Z`          | The pyde validator binary (future) |

Each tag carries: signed platform tarballs (Linux x86_64 + aarch64, macOS arm64, Windows x86_64), sha256 manifests, sigstore cosign signatures + certificates. Pre-releases use a hyphenated suffix (`-alpha`, `-testnet.1`, `-rc1`); stable tags are bare `vX.Y.Z`.

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

## Where bugs / PRs / docs live

- **otigen** issues, PRs, source, docs → [pyde-net/otigen](https://github.com/pyde-net/otigen) (private during pre-mainnet)
- **Engine** issues, PRs, source → pyde-net/engine (private during pre-mainnet)
- **Pyde Network book + companion specs** → [pyde-net/pyde-book](https://github.com/pyde-net/pyde-book)
- **Pyde Improvement Proposals (PIPs)** → pyde-net/pips

This repo accepts no PRs against its contents — every file is generated by the upstream release workflows.

## License

The release artifacts here are licensed per their source repo (Apache-2.0 for otigen).
