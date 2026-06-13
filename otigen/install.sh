#!/usr/bin/env bash
# otigen install / update / uninstall script.
#
# Supported platforms: macOS arm64, Linux x86_64, Linux aarch64.
# Windows users: run from Git Bash or WSL.
#
# ── Usage ──────────────────────────────────────────────────────────
#
#     # Install or update (re-running over an existing install is
#     # the upgrade path — same shape as rustup-init / deno install)
#     curl -fsSL https://raw.githubusercontent.com/pyde-net/otigen/main/install.sh | bash
#
#     # Pin a specific release tag
#     curl -fsSL https://raw.githubusercontent.com/pyde-net/otigen/main/install.sh \
#         | bash -s -- --version v0.1.0-alpha.0
#
#     # Remove the installed binary
#     curl -fsSL https://raw.githubusercontent.com/pyde-net/otigen/main/install.sh \
#         | bash -s -- --uninstall
#
# Run with `--help` for the full flag catalog (including --update
# alias, --prefix, --check-only).
#
# ── Auth ───────────────────────────────────────────────────────────
#
# The script picks one of three paths automatically, in this order:
#
#   1. **Anonymous curl** (the public-release path). If the repo's
#      public-API endpoint returns 200 without credentials, no auth
#      is needed — the install proceeds purely over curl. This is
#      what every public-mainnet user will hit; curl ships on every
#      mainstream OS by default.
#   2. `gh` (the GitHub CLI) — used when the repo is private AND `gh`
#      is installed AND authenticated. No env var required.
#   3. `GITHUB_TOKEN` — a personal access token with `Contents: read`
#      on `pyde-net/otigen`. Required as an env var if the repo is
#      private and `gh` isn't available.
#
# The first reachability probe takes ~100-300 ms; the price for
# never asking the public user to set up credentials they don't
# need.

set -euo pipefail

# Binaries are published to the public mirror repo
# `pyde-net/test-releases` so authors can install over plain curl without
# pulling the otigen source. Tags on the mirror are prefixed per
# product (`otigen-vX.Y.Z`, `engine-vX.Y.Z`, …) so the same mirror
# can host every Pyde toolchain artifact long-term.
REPO="pyde-net/test-releases"
TAG_PREFIX="otigen-"
DEFAULT_PREFIX="${HOME}/.otigen/bin"

# Mutable globals — populated by flag parsing + the mode handlers.
MODE="install"           # install | update | uninstall
PIN_VERSION=""           # empty = resolve "latest release" at runtime
PREFIX="${OTIGEN_INSTALL_DIR:-${DEFAULT_PREFIX}}"
CHECK_ONLY=0
MODIFY_PATH=1            # set to 0 by --no-modify-path
TARGET=""                # filled in by detect_platform
TAG=""                   # filled in by resolve_version — full mirror tag (`otigen-vX.Y.Z`)
VERSION=""               # filled in by resolve_version — stripped (`vX.Y.Z`); embedded in asset names
USE_GH=0                 # filled in by resolve_auth
USE_ANON=0               # filled in by resolve_auth — anonymous curl path

# Sentinel comments wrapping the install.sh-managed PATH line.
# Edits between the markers are owned by this script; --uninstall
# strips the whole block. Don't change the strings — they're the
# idempotency key.
PATH_MARKER_BEGIN="# >>> otigen install.sh path >>>"
PATH_MARKER_END="# <<< otigen install.sh path <<<"

# ── log helpers ────────────────────────────────────────────────────
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
otigen install.sh — install / update / uninstall the otigen toolchain

Usage:
  install.sh [MODE_FLAG] [OPTIONS]

Mode flags (mutually exclusive):
  (none)                Install the latest release, or replace an existing
                        install with the latest (re-running the script is
                        the upgrade path).
  --update              Alias for the default behavior. Useful in scripts
                        when you want the intent to be explicit.
  --uninstall           Remove the installed binary.

Options:
  --version <tag>       Pin a specific release tag (e.g. v0.1.0-alpha.0)
                        instead of the latest. Works with --update too.
  --prefix <dir>        Install location. Default: ~/.otigen/bin
                        (override via OTIGEN_INSTALL_DIR env var too).
  --no-modify-path      Skip the shell-rc PATH edit. Default is to detect
                        your shell ($SHELL: zsh / bash / fish) and append
                        the export line to the matching rc with marker
                        comments so --uninstall can strip it cleanly.
  --check-only          Dry run. Print what the script would do and exit;
                        no downloads, no writes.
  -h, --help            Show this catalog.

Environment:
  GITHUB_TOKEN          Personal access token with Contents: read on the
                        repo. Required if `gh` isn't installed / authed.
  OTIGEN_INSTALL_DIR    Same as --prefix.

Examples:
  install.sh                              # install latest
  install.sh --update                     # update to latest
  install.sh --version v0.1.0-alpha.0     # pin a specific tag
  install.sh --uninstall                  # remove
  install.sh --check-only --update        # see what an update would do
EOF
}

# ── flag parsing ───────────────────────────────────────────────────
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update)       MODE="update";       shift ;;
            --uninstall)    MODE="uninstall";    shift ;;
            --check-only)   CHECK_ONLY=1;        shift ;;
            --version)
                [[ $# -ge 2 ]] || die "--version requires a tag (e.g. v0.1.0-alpha.0)"
                PIN_VERSION="$2";    shift 2 ;;
            --version=*)    PIN_VERSION="${1#*=}";    shift ;;
            --prefix)
                [[ $# -ge 2 ]] || die "--prefix requires a directory"
                PREFIX="$2";         shift 2 ;;
            --prefix=*)     PREFIX="${1#*=}";    shift ;;
            --no-modify-path) MODIFY_PATH=0;     shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              die "Unknown argument: $1  (run with --help)" ;;
        esac
    done
}

# ── platform detection ─────────────────────────────────────────────
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64)   TARGET="aarch64-apple-darwin" ;;
                x86_64)  die "macOS x86_64 is not shipped in this release. Use an arm64 Mac, or build from source." ;;
                *)       die "Unsupported macOS arch: $(uname -m)" ;;
            esac ;;
        Linux)
            case "$(uname -m)" in
                x86_64)  TARGET="x86_64-unknown-linux-gnu" ;;
                aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
                *)       die "Unsupported Linux arch: $(uname -m)" ;;
            esac ;;
        *)
            die "Unsupported OS: $(uname -s). On Windows, run install.sh from Git Bash or WSL." ;;
    esac
}

# ── auth resolution ────────────────────────────────────────────────
resolve_auth() {
    # Anonymous-first probe. GitHub's repos endpoint returns 200 for
    # public repos without credentials and 404 for private ones. We
    # use that as our reachability check — if the repo is public, we
    # short-circuit straight into the curl path and never ask the
    # user to configure auth they don't need.
    if curl -fsSL -o /dev/null \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO}" >/dev/null 2>&1; then
        USE_ANON=1
        log "Public release — installing without auth."
        return
    fi

    # Private repo (or GitHub API unreachable). Fall through to the
    # authenticated paths.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        USE_GH=1
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        USE_GH=0
    else
        die "This repo is private — authenticate via one of:
    - install gh (https://cli.github.com) + run \`gh auth login\`, OR
    - export GITHUB_TOKEN=<personal-access-token> (needs Contents: read on ${REPO})"
    fi
}

# ── version resolution ─────────────────────────────────────────────
#
# The /releases/latest endpoint excludes pre-releases, so we use the
# /releases listing (sorted newest-first) and take the head.
resolve_version() {
    if [[ -n "$PIN_VERSION" ]]; then
        # Caller may pass either `vX.Y.Z` or the full prefixed tag
        # `otigen-vX.Y.Z` — accept both shapes.
        if [[ "$PIN_VERSION" == ${TAG_PREFIX}* ]]; then
            TAG="$PIN_VERSION"
            VERSION="${PIN_VERSION#${TAG_PREFIX}}"
        else
            VERSION="$PIN_VERSION"
            TAG="${TAG_PREFIX}${PIN_VERSION}"
        fi
        return
    fi
    # The mirror hosts artifacts for every Pyde toolchain (otigen,
    # engine, …) under one release timeline, so we filter by tag
    # prefix to pick the freshest one for THIS product. Fetch the
    # last 30 releases and take the first one whose tag name starts
    # with `$TAG_PREFIX`.
    local raw
    if (( USE_GH )); then
        raw=$(gh release list --repo "$REPO" --limit 30 --json tagName \
            --jq "[.[] | select(.tagName | startswith(\"${TAG_PREFIX}\"))][0].tagName // empty")
    elif (( USE_ANON )); then
        raw=$(curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO}/releases?per_page=30" \
            | python3 -c "
import sys, json
prefix = '${TAG_PREFIX}'
data = json.load(sys.stdin)
for r in data:
    if r['tag_name'].startswith(prefix):
        print(r['tag_name'])
        break
")
    else
        raw=$(curl -fsSL \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${REPO}/releases?per_page=30" \
            | python3 -c "
import sys, json
prefix = '${TAG_PREFIX}'
data = json.load(sys.stdin)
for r in data:
    if r['tag_name'].startswith(prefix):
        print(r['tag_name'])
        break
")
    fi
    [[ -n "$raw" ]] || die "couldn't resolve latest ${TAG_PREFIX%-} release on ${REPO}"
    TAG="$raw"
    VERSION="${raw#${TAG_PREFIX}}"
}

# ── installed-binary heuristic ─────────────────────────────────────
#
# `otigen --version` prints `otigen 0.1.0 (sha <hash>, release)`.
# We use it as a fingerprint for "is something installed at $PREFIX",
# not for version comparison — tag vs cargo version don't align
# cleanly. --update therefore always re-downloads + replaces.
installed_at_prefix() {
    [[ -x "${PREFIX}/otigen" ]]
}

# ── modes ──────────────────────────────────────────────────────────
mode_uninstall() {
    local target="${PREFIX}/otigen"
    local binary_present=0
    local rc_managed=()
    if [[ -e "$target" ]]; then
        binary_present=1
    fi

    # Find every shell rc this script may have written to.
    local candidate
    for candidate in "${ZDOTDIR:-$HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.config/fish/config.fish"; do
        if [[ -f "$candidate" ]] && grep -Fq "${PATH_MARKER_BEGIN}" "$candidate" 2>/dev/null; then
            rc_managed+=("$candidate")
        fi
    done

    if (( ! binary_present )) && (( ${#rc_managed[@]} == 0 )); then
        log "Nothing to remove — no binary at ${target} and no install.sh-managed PATH lines found."
        return 0
    fi

    if (( CHECK_ONLY )); then
        if (( binary_present )); then
            log "[check-only] would remove ${target}"
        fi
        for candidate in ${rc_managed[@]+"${rc_managed[@]}"}; do
            log "[check-only] would strip the install.sh-managed PATH block from ${candidate}"
        done
        return 0
    fi

    if (( binary_present )); then
        rm -f "$target"
        log "Removed ${target}"
    fi

    # Strip the marker-wrapped block from each managed rc. Uses a
    # portable sed -i invocation: macOS's BSD sed needs `-i ''`
    # (empty extension), GNU sed allows just `-i`. We work around by
    # writing to a tempfile and moving back — same shape, no platform fork.
    for candidate in ${rc_managed[@]+"${rc_managed[@]}"}; do
        local tmp_rc
        tmp_rc=$(mktemp)
        awk -v begin="$PATH_MARKER_BEGIN" -v end="$PATH_MARKER_END" '
            $0 == begin { skip = 1; next }
            skip && $0 == end { skip = 0; next }
            skip { next }
            { print }
        ' "$candidate" > "$tmp_rc"
        # Trim any trailing blank lines the block-removal left behind.
        # Keeps the file tidy for users who care.
        awk 'NF { last = NR; lines[NR] = $0; next } { lines[NR] = $0 } END { for (i = 1; i <= last; i++) print lines[i] }' "$tmp_rc" > "${tmp_rc}.trimmed"
        mv "${tmp_rc}.trimmed" "$candidate"
        rm -f "$tmp_rc"
        log "Stripped install.sh-managed PATH block from ${candidate}"
    done

    if (( binary_present )) && [[ -d "$PREFIX" ]] && [[ -z "$(ls -A "$PREFIX")" ]]; then
        rmdir "$PREFIX" 2>/dev/null && log "Removed empty ${PREFIX}"
    fi
}

mode_install_or_update() {
    detect_platform
    resolve_auth
    resolve_version

    log "Platform: ${TARGET}"
    log "Target version: ${VERSION}"
    log "Install prefix: ${PREFIX}"

    # Re-running the script over an existing install is the upgrade
    # path — same shape as rustup-init.sh, deno install, etc. We
    # don't gate on the installed/missing distinction; the verb is
    # always "make ${PREFIX}/otigen point at ${VERSION}".
    if installed_at_prefix; then
        log "Existing install detected at ${PREFIX}/otigen — replacing with ${VERSION}"
    fi

    if (( CHECK_ONLY )); then
        if installed_at_prefix; then
            log "[check-only] would replace ${PREFIX}/otigen with otigen ${VERSION} for ${TARGET}"
        else
            log "[check-only] would download otigen ${VERSION} for ${TARGET} and install to ${PREFIX}/otigen"
        fi
        return 0
    fi

    download_and_install
}

# ── download + verify + install ────────────────────────────────────
download_and_install() {
    local asset="otigen-${VERSION}-${TARGET}.tar.gz"
    local tmp
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064 -- $tmp captured at trap-set time, intentional.
    trap "rm -rf '${tmp}'" EXIT
    cd "$tmp"

    log "Downloading ${asset}"
    if (( USE_GH )); then
        gh release download "$TAG" --repo "$REPO" \
            --pattern "$asset" \
            --pattern "${asset}.sha256"
    else
        # Build the meta fetch + per-asset GET commands once; anon vs
        # token-authed branches only differ by the Authorization header.
        local meta
        if (( USE_ANON )); then
            meta=$(curl -fsSL \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${REPO}/releases/tags/${TAG}")
        else
            meta=$(curl -fsSL \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/${REPO}/releases/tags/${TAG}")
        fi
        local name
        for name in "$asset" "${asset}.sha256"; do
            local url
            # Anonymous downloads use `browser_download_url` (the public
            # CDN-served path); authenticated downloads use `url` with
            # the `application/octet-stream` accept header (which
            # GitHub's API resolves to the same artifact behind auth).
            local url_key
            if (( USE_ANON )); then
                url_key="browser_download_url"
            else
                url_key="url"
            fi
            url=$(printf '%s' "$meta" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if a['name'] == '$name':
        print(a['$url_key'])
        break
else:
    sys.exit('asset not found: $name')
")
            if (( USE_ANON )); then
                curl -fsSL -o "$name" "$url"
            else
                curl -fsSL \
                    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                    -H "Accept: application/octet-stream" \
                    -o "$name" "$url"
            fi
        done
    fi

    log "Verifying sha256"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c "${asset}.sha256"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "${asset}.sha256"
    else
        die "neither shasum nor sha256sum is on PATH — can't verify the artifact"
    fi

    log "Extracting"
    tar xzf "$asset"
    local staging="otigen-${VERSION}-${TARGET}"
    [[ -x "${staging}/otigen" ]] || die "extracted tarball is missing the otigen binary"

    mkdir -p "$PREFIX"
    install -m 0755 "${staging}/otigen" "${PREFIX}/otigen"
    log "Installed ${VERSION} to ${PREFIX}/otigen"

    ensure_on_path
}

# ── shell-rc PATH management ───────────────────────────────────────
#
# Detect the user's shell from $SHELL and append a marker-wrapped
# `export PATH=...` block to its rc file if PREFIX isn't on PATH
# yet. The wrapper markers make `--uninstall` removal a no-op grep.
#
# Idempotency: if PREFIX is already on PATH, OR the marker block is
# already present in the rc file, do nothing. Safe to re-run.
#
# Override: --no-modify-path skips this step (e.g. for users with
# managed dotfile repos or unusual shell setups).
ensure_on_path() {
    # Already on PATH — nothing to do.
    case ":$PATH:" in
        *":${PREFIX}:"*)
            log "Done. ${PREFIX} is already on PATH — run \`otigen --version\` to confirm."
            return 0
            ;;
    esac

    if (( ! MODIFY_PATH )); then
        warn "${PREFIX} is not on PATH and --no-modify-path is set. Add this to your shell rc manually:"
        printf '\n    export PATH="%s:$PATH"\n\n' "$PREFIX"
        return 0
    fi

    local rc_file rc_kind shell_name
    shell_name="${SHELL##*/}"
    case "$shell_name" in
        zsh)
            rc_file="${ZDOTDIR:-$HOME}/.zshrc"
            rc_kind="zsh"
            ;;
        bash)
            # macOS Terminal starts login shells (~/.bash_profile);
            # most Linux distros run interactive non-login
            # (~/.bashrc). Pick the one that exists, falling back
            # to the platform default if neither is there yet.
            if [[ -f "${HOME}/.bashrc" ]]; then
                rc_file="${HOME}/.bashrc"
            elif [[ -f "${HOME}/.bash_profile" ]]; then
                rc_file="${HOME}/.bash_profile"
            elif [[ "$(uname -s)" == "Darwin" ]]; then
                rc_file="${HOME}/.bash_profile"
            else
                rc_file="${HOME}/.bashrc"
            fi
            rc_kind="bash"
            ;;
        fish)
            rc_file="${HOME}/.config/fish/config.fish"
            rc_kind="fish"
            ;;
        *)
            warn "${PREFIX} is not on PATH and we don't recognize \$SHELL=${SHELL:-<unset>}."
            warn "Add this line to your shell's rc file manually:"
            printf '\n    export PATH="%s:$PATH"\n\n' "$PREFIX"
            return 0
            ;;
    esac

    # Idempotency — if the marker or the literal PREFIX is already
    # in the rc file, leave it alone. Don't double-add.
    if [[ -f "$rc_file" ]] && grep -Fq "${PATH_MARKER_BEGIN}" "$rc_file" 2>/dev/null; then
        log "${PREFIX} already managed by install.sh in ${rc_file} — leaving it alone."
        log "To activate it in this shell: \`source ${rc_file}\` (or open a new shell)."
        return 0
    fi
    if [[ -f "$rc_file" ]] && grep -Fq "${PREFIX}" "$rc_file" 2>/dev/null; then
        log "${PREFIX} already referenced in ${rc_file} (added outside install.sh) — leaving it alone."
        log "To activate it in this shell: \`source ${rc_file}\` (or open a new shell)."
        return 0
    fi

    # Append the marker-wrapped block. mkdir -p the parent dir so
    # fish's nested ~/.config/fish/ works on a fresh machine.
    mkdir -p "$(dirname "$rc_file")"
    {
        printf '\n%s\n' "$PATH_MARKER_BEGIN"
        printf '# Added by otigen install.sh — safe to remove if you uninstall.\n'
        if [[ "$rc_kind" == "fish" ]]; then
            printf 'set -gx PATH "%s" $PATH\n' "$PREFIX"
        else
            printf 'export PATH="%s:$PATH"\n' "$PREFIX"
        fi
        printf '%s\n' "$PATH_MARKER_END"
    } >> "$rc_file"

    log "Added ${PREFIX} to PATH in ${rc_file}"
    log "Activate it in this shell:  source ${rc_file}"
    log "Or open a new terminal. Then run \`otigen --version\` to confirm."
}


# ── entry point ────────────────────────────────────────────────────
main() {
    parse_flags "$@"
    case "$MODE" in
        uninstall)         mode_uninstall ;;
        install|update)    mode_install_or_update ;;
    esac
}

main "$@"
