#!/usr/bin/env bash
# Stages the pinned @clawjs/cli release plus a Node runtime into
# Clawix.app/Contents/Resources/clawjs/. ClawJSRuntime.swift expects
# this exact layout at runtime; the release build's codesign --verify
# --deep --strict pass exercises every native module sealed inside.
#
# Usage:
#   bash bundle_clawjs.sh <bundle-path>
#
# Inputs:
#   macos/CLAWJS_VERSION  → @clawjs/cli release to install
#                                 (read via _emit_version.sh).
#   CLAWJS_NODE_VERSION         → Node release to bundle (default 20.19.6;
#                                 ABI 115, matching the better-sqlite3
#                                 prebuilds the install script grabs).
#   CLAWJS_SIGN_IDENTITY        → codesign identity to apply to the bundled
#                                 Node binary and every nested .node. Falls
#                                 back to ad-hoc when empty / "-".
#   CLAWJS_SIGN_OPTS            → extra codesign flags (e.g.
#                                 "--options runtime --timestamp" for
#                                 release / notarization).
#
# Outputs:
#   <bundle>/Contents/Resources/clawjs/{node, package.json, node_modules/}
#
# Idempotency:
#   Skips re-install when <bundle>/Contents/Helpers/clawjs/package.json
#   already declares CLAWJS_VERSION. The cache at
#   macos/build/clawjs-cache/<version>/ is reused across runs and
#   across .app bundles so dev iteration stays cheap.
#
# Architecture:
#   arm64 only, matching `swift build -c release` (host build, no
#   universal-binary post-merge). When Clawix itself goes universal,
#   this script must lipo-merge x86_64 prebuilds into the .node files
#   and a universal node binary.

set -euo pipefail

BUNDLE_DIR="${1:-}"
if [[ -z "$BUNDLE_DIR" ]]; then
    echo "ERROR: bundle path missing. Usage: bundle_clawjs.sh <bundle-path>" >&2
    exit 1
fi
if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "ERROR: bundle path does not exist: $BUNDLE_DIR" >&2
    exit 1
fi
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Pull CLAWJS_VERSION (and the rest of the version contract) into scope.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_emit_version.sh"

NODE_VERSION="${CLAWJS_NODE_VERSION:-20.19.6}"
NODE_ARCH="arm64"
SIGN_ID="${CLAWJS_SIGN_IDENTITY:--}"
SIGN_OPTS="${CLAWJS_SIGN_OPTS:-}"

CLAWJS_DEST="$BUNDLE_DIR/Contents/Resources/clawjs"
CACHE_ROOT="$PROJECT_DIR/build/clawjs-cache/$CLAWJS_VERSION"
STAGE_DIR="$CACHE_ROOT/stage"
NODE_TARBALL="$CACHE_ROOT/node-v${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
NODE_DIR="$CACHE_ROOT/node-v${NODE_VERSION}-darwin-${NODE_ARCH}"

# Reads the "version" field from a package.json without pulling in jq.
read_pkg_version() {
    local file="$1"
    [[ -f "$file" ]] || { echo ""; return; }
    /usr/bin/python3 - "$file" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("version", ""))
except Exception:
    print("")
PY
}

# 0) Idempotency: bundle already at the right version → done. The stage
#    package.json is just a manifest declaring the dep, so check the
#    actually-installed @clawjs/cli package.json that holds the real
#    version field.
if [[ -z "${CLAWJS_DEV_OVERLAY:-}" && "$(read_pkg_version "$CLAWJS_DEST/node_modules/@clawjs/cli/package.json")" == "$CLAWJS_VERSION" ]]; then
    echo "==> ClawJS bundle already at $CLAWJS_VERSION, skipping"
    exit 0
fi

mkdir -p "$CACHE_ROOT"

# 1) Locate npm. The user's nvm shell shadow breaks invocation in
#    non-interactive shells; bypass it with absolute paths and run
#    npm-cli.js through a Node binary that actually starts.
NODE_FOR_NPM=""
for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
        NODE_FOR_NPM="$candidate"
        break
    fi
done
if [[ -z "$NODE_FOR_NPM" ]]; then
    echo "ERROR: working Node not found in /opt/homebrew/bin or /usr/local/bin" >&2
    exit 1
fi
NPM_CLI=""
for candidate in \
    /opt/homebrew/lib/node_modules/npm/bin/npm-cli.js \
    /usr/local/lib/node_modules/npm/bin/npm-cli.js
do
    [[ -f "$candidate" ]] && NPM_CLI="$candidate" && break
done
if [[ ! -f "$NPM_CLI" ]]; then
    echo "ERROR: npm CLI entrypoint not found" >&2
    exit 1
fi
run_npm() {
    PATH="$(dirname "$NODE_FOR_NPM"):$PATH" "$NODE_FOR_NPM" "$NPM_CLI" "$@"
}

# 2) Stage the install. Cache by version: when CLAWJS_VERSION bumps the
#    next run starts from a fresh stage; otherwise we re-use whatever
#    npm resolved last time (deterministic by package-lock.json).
STAGE_CLI_PKG="$STAGE_DIR/node_modules/@clawjs/cli/package.json"
if [[ "$(read_pkg_version "$STAGE_CLI_PKG")" != "$CLAWJS_VERSION" ]]; then
    echo "==> Installing @clawjs/cli@$CLAWJS_VERSION (arm64) into stage"
    rm -rf "$STAGE_DIR"
    mkdir -p "$STAGE_DIR"
    cat > "$STAGE_DIR/package.json" <<EOF
{
  "name": "clawix-clawjs-bundle",
  "private": true,
  "dependencies": {
    "@clawjs/cli": "${CLAWJS_VERSION}"
  }
}
EOF
    (
        cd "$STAGE_DIR"
        npm_config_arch=arm64 \
        npm_config_target_arch=arm64 \
        npm_config_target_platform=darwin \
        run_npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-bin-links 2>&1 | tail -3
    )
    if [[ "$(read_pkg_version "$STAGE_CLI_PKG")" != "$CLAWJS_VERSION" ]]; then
        echo "ERROR: npm install resolved a @clawjs/cli version different from $CLAWJS_VERSION" >&2
        exit 1
    fi
fi

# 3) Resolve the Node runtime tarball, cached per version.
if [[ ! -d "$NODE_DIR" ]]; then
    if [[ ! -f "$NODE_TARBALL" ]]; then
        echo "==> Downloading Node v${NODE_VERSION} (${NODE_ARCH})"
        curl -L --fail --silent --show-error \
            -o "$NODE_TARBALL.tmp" \
            "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
        mv "$NODE_TARBALL.tmp" "$NODE_TARBALL"
    fi
    echo "==> Extracting Node"
    tar -C "$CACHE_ROOT" -xzf "$NODE_TARBALL"
fi

# 4) Materialize Contents/Helpers/clawjs/. Always rebuild from the cache;
#    cheap (a local tree copy) and avoids stale state from older versions.
echo "==> Assembling $CLAWJS_DEST"
rm -rf "$CLAWJS_DEST"
mkdir -p "$CLAWJS_DEST"

cp "$STAGE_DIR/package.json" "$CLAWJS_DEST/package.json"
cp -R "$STAGE_DIR/node_modules" "$CLAWJS_DEST/node_modules"
cp "$NODE_DIR/bin/node" "$CLAWJS_DEST/node"
chmod +x "$CLAWJS_DEST/node"

# Sanity guard: this is the version pin that the release pipeline relies
# on. If it ever drifts (registry tampering, dependency hijack), abort.
INSTALLED="$(read_pkg_version "$CLAWJS_DEST/node_modules/@clawjs/cli/package.json")"
if [[ "$INSTALLED" != "$CLAWJS_VERSION" ]]; then
    echo "ERROR: bundled @clawjs/cli is $INSTALLED, expected $CLAWJS_VERSION" >&2
    exit 1
fi

# Dev overlay: when CLAWJS_DEV_OVERLAY points to a local clawjs monorepo
# (e.g. /Users/.../clawjs), copy the launcher bin/ scripts and the
# @clawjs/database source over the bundled ones. Lets a developer iterate
# on launcher .mjs files (database-server-launcher.mjs,
# vault-server-launcher.mjs, …) and on the database package without
# republishing npm. No-op in CI / release builds.
if [[ -n "${CLAWJS_DEV_OVERLAY:-}" ]]; then
    OVERLAY_DEPS_READY=0
    ensure_overlay_dependencies() {
        [[ "$OVERLAY_DEPS_READY" -eq 0 ]] || return 0
        OVERLAY_DEPS_READY=1
        if [[ -f "$CLAWJS_DEV_OVERLAY/package.json" && -f "$CLAWJS_DEV_OVERLAY/package-lock.json" && ! -d "$CLAWJS_DEV_OVERLAY/node_modules" ]]; then
            echo "==> Dev overlay: installing workspace dependencies"
            run_npm --prefix "$CLAWJS_DEV_OVERLAY" install --ignore-scripts --no-audit --no-fund >/dev/null
        fi
        if [[ -f "$CLAWJS_DEV_OVERLAY/packages/clawjs-core/package.json" ]]; then
            echo "==> Dev overlay: building @clawjs/core"
            PATH="/opt/homebrew/bin:/usr/local/bin:$CLAWJS_DEV_OVERLAY/node_modules/.bin:$PATH" \
                run_npm --prefix "$CLAWJS_DEV_OVERLAY" run build --workspace @clawjs/core >/dev/null
        fi
    }

    build_overlay_package() {
        local pkg_dir="$1"
        [[ -f "$pkg_dir/package.json" ]] || return 0
        if /usr/bin/python3 - "$pkg_dir/package.json" <<'PY'
import json, sys
try:
    scripts = json.load(open(sys.argv[1])).get("scripts", {})
except Exception:
    scripts = {}
sys.exit(0 if scripts.get("build") else 1)
PY
        then
            ensure_overlay_dependencies
            if [[ -f "$pkg_dir/package-lock.json" && ! -d "$pkg_dir/node_modules" ]]; then
                echo "==> Dev overlay: installing $(basename "$pkg_dir") dependencies"
                run_npm --prefix "$pkg_dir" install --ignore-scripts --no-audit --no-fund >/dev/null
            fi
            if [[ -f "$pkg_dir/ui/package.json" && -f "$pkg_dir/ui/package-lock.json" && ! -d "$pkg_dir/ui/node_modules" ]]; then
                echo "==> Dev overlay: installing $(basename "$pkg_dir") UI dependencies"
                run_npm --prefix "$pkg_dir/ui" install --ignore-scripts --no-audit --no-fund >/dev/null
            fi
            PATH="/opt/homebrew/bin:/usr/local/bin:$CLAWJS_DEV_OVERLAY/node_modules/.bin:$pkg_dir/node_modules/.bin:$PATH" \
                run_npm --prefix "$pkg_dir" run build >/dev/null
        fi
    }

    copy_overlay_core() {
        local dest="$1"
        local overlay_core="$CLAWJS_DEV_OVERLAY/packages/clawjs-core"
        [[ -d "$overlay_core" ]] || return 0
        ensure_overlay_dependencies
        echo "==> Dev overlay: copying $overlay_core → $dest"
        rm -rf "$dest"
        mkdir -p "$(dirname "$dest")"
        cp -R "$overlay_core" "$dest"
    }

    OVERLAY_BIN="$CLAWJS_DEV_OVERLAY/packages/clawjs/bin"
    if [[ ! -d "$OVERLAY_BIN" && -d "$CLAWJS_DEV_OVERLAY/bin" ]]; then
        OVERLAY_BIN="$CLAWJS_DEV_OVERLAY/bin"
    fi
    if [[ -d "$OVERLAY_BIN" ]]; then
        echo "==> Dev overlay: copying $OVERLAY_BIN → $CLAWJS_DEST/node_modules/@clawjs/cli/bin"
        cp -R "$OVERLAY_BIN/." "$CLAWJS_DEST/node_modules/@clawjs/cli/bin/"
    fi
    copy_overlay_core "$CLAWJS_DEST/node_modules/@clawjs/core"
    OVERLAY_DB="$CLAWJS_DEV_OVERLAY/packages/clawjs-database"
    if [[ -d "$OVERLAY_DB" ]]; then
        build_overlay_package "$OVERLAY_DB"
        echo "==> Dev overlay: copying $OVERLAY_DB → $CLAWJS_DEST/node_modules/@clawjs/database"
        rm -rf "$CLAWJS_DEST/node_modules/@clawjs/database"
        mkdir -p "$CLAWJS_DEST/node_modules/@clawjs"
        cp -R "$OVERLAY_DB" "$CLAWJS_DEST/node_modules/@clawjs/database"
        (
            cd "$CLAWJS_DEST/node_modules/@clawjs/database"
            npm_config_arch=arm64 \
            npm_config_target_arch=arm64 \
            npm_config_target_platform=darwin \
            run_npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-bin-links 2>&1 | tail -3
        )
        rm -rf "$CLAWJS_DEST/node_modules/@clawjs/database/node_modules/better-sqlite3"
        copy_overlay_core "$CLAWJS_DEST/node_modules/@clawjs/database/node_modules/@clawjs/core"
    fi
    # Vault server: launchers resolve `<HERE>/../../../vault/dist/server.js`
    # from @clawjs/cli/bin, i.e. node_modules/vault/dist/server.js.
    OVERLAY_VAULT="$CLAWJS_DEV_OVERLAY/vault"
    if [[ -d "$OVERLAY_VAULT" ]]; then
        build_overlay_package "$OVERLAY_VAULT"
        echo "==> Dev overlay: copying $OVERLAY_VAULT/dist → $CLAWJS_DEST/node_modules/vault/dist"
        rm -rf "$CLAWJS_DEST/node_modules/vault/dist"
        mkdir -p "$CLAWJS_DEST/node_modules/vault"
        cp -R "$OVERLAY_VAULT/dist" "$CLAWJS_DEST/node_modules/vault/dist"
        if [[ -d "$OVERLAY_VAULT/node_modules" ]]; then
            rm -rf "$CLAWJS_DEST/node_modules/vault/node_modules"
            cp -R "$OVERLAY_VAULT/node_modules" "$CLAWJS_DEST/node_modules/vault/node_modules"
            rm -rf "$CLAWJS_DEST/node_modules/vault/node_modules/better-sqlite3"
        fi
    fi
    # Memory server: same layout as vault.
    OVERLAY_MEMORY="$CLAWJS_DEV_OVERLAY/memory"
    if [[ -d "$OVERLAY_MEMORY" ]]; then
        build_overlay_package "$OVERLAY_MEMORY"
        echo "==> Dev overlay: copying $OVERLAY_MEMORY/dist → $CLAWJS_DEST/node_modules/memory/dist"
        rm -rf "$CLAWJS_DEST/node_modules/memory/dist"
        mkdir -p "$CLAWJS_DEST/node_modules/memory"
        cp -R "$OVERLAY_MEMORY/dist" "$CLAWJS_DEST/node_modules/memory/dist"
        # node_modules of the memory pkg are needed for native deps.
        if [[ -d "$OVERLAY_MEMORY/node_modules" ]]; then
            rm -rf "$CLAWJS_DEST/node_modules/memory/node_modules"
            cp -R "$OVERLAY_MEMORY/node_modules" "$CLAWJS_DEST/node_modules/memory/node_modules"
            rm -rf "$CLAWJS_DEST/node_modules/memory/node_modules/better-sqlite3"
        fi
    fi
    # Drive surface.
    OVERLAY_DRIVE="$CLAWJS_DEV_OVERLAY/drive"
    if [[ -d "$OVERLAY_DRIVE" ]]; then
        build_overlay_package "$OVERLAY_DRIVE"
        echo "==> Dev overlay: copying $OVERLAY_DRIVE/dist → $CLAWJS_DEST/node_modules/drive/dist"
        rm -rf "$CLAWJS_DEST/node_modules/drive/dist"
        mkdir -p "$CLAWJS_DEST/node_modules/drive"
        cp -R "$OVERLAY_DRIVE/dist" "$CLAWJS_DEST/node_modules/drive/dist"
        if [[ -d "$OVERLAY_DRIVE/node_modules" ]]; then
            rm -rf "$CLAWJS_DEST/node_modules/drive/node_modules"
            cp -R "$OVERLAY_DRIVE/node_modules" "$CLAWJS_DEST/node_modules/drive/node_modules"
            rm -rf "$CLAWJS_DEST/node_modules/drive/node_modules/better-sqlite3"
        fi
    fi
    # Telegram surface: launcher tries
    # `<HERE>/../../../telegram/dist/server.js` next to the cli bin/.
    OVERLAY_TELEGRAM="$CLAWJS_DEV_OVERLAY/telegram"
    if [[ -d "$OVERLAY_TELEGRAM" ]]; then
        build_overlay_package "$OVERLAY_TELEGRAM"
        echo "==> Dev overlay: copying $OVERLAY_TELEGRAM/dist → $CLAWJS_DEST/node_modules/telegram/dist"
        rm -rf "$CLAWJS_DEST/node_modules/telegram/dist"
        mkdir -p "$CLAWJS_DEST/node_modules/telegram"
        cp -R "$OVERLAY_TELEGRAM/dist" "$CLAWJS_DEST/node_modules/telegram/dist"
        if [[ -d "$OVERLAY_TELEGRAM/node_modules" ]]; then
            rm -rf "$CLAWJS_DEST/node_modules/telegram/node_modules"
            cp -R "$OVERLAY_TELEGRAM/node_modules" "$CLAWJS_DEST/node_modules/telegram/node_modules"
        fi
    fi
fi

(
    cd "$CLAWJS_DEST"
    npm_config_nodedir="$NODE_DIR" \
    npm_config_arch=arm64 \
    npm_config_target_arch=arm64 \
    npm_config_target_platform=darwin \
    PATH="$CLAWJS_DEST:$PATH" "$CLAWJS_DEST/node" "$NPM_CLI" rebuild better-sqlite3 --build-from-source 2>&1 | tail -3
)

# 5) Re-sign every nested native module and the Node binary. npm-installed
#    .node prebuilds ship as linker-signed adhoc; the outer .app codesign
#    does not use --deep (so it would not re-sign them), and the release
#    pipeline's `codesign --verify --deep --strict` exercises every one.
sign_one() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    if [[ "$SIGN_ID" != "-" && -n "$SIGN_ID" ]]; then
        # shellcheck disable=SC2086
        if codesign --force --sign "$SIGN_ID" $SIGN_OPTS "$target" 2>/dev/null; then
            return
        fi
    fi
    # Ad-hoc fallback. Used when SIGN_ID is empty/"-" (dev without
    # .signing.env) or when the configured identity is unavailable.
    codesign --force --sign - --timestamp=none "$target"
}

while IFS= read -r native; do
    sign_one "$native"
done < <(find "$CLAWJS_DEST" -type f -name "*.node")

sign_one "$CLAWJS_DEST/node"

echo "==> ClawJS bundle ready at $CLAWJS_DEST (clawjs $CLAWJS_VERSION, node $NODE_VERSION $NODE_ARCH)"
