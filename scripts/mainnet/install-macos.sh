#!/usr/bin/env bash
# Download the Block Zero macOS wallet + tools (Block Zero.app, bitcoind,
# bitcoin-cli). Apple Silicon (M1/M2/M3/M4) only — the same GUI wallet as on
# Windows (bitcoin-qt), branded as "Block Zero".
#
# Usage:
#   ./install-macos.sh                 # latest release
#   ./install-macos.sh --force         # re-download even if already installed
#   VERSION=v1.0.0-rc24 ./install-macos.sh
#
# Then:
#   open "$HOME/Applications/Block Zero.app"   # GUI wallet
#   ./mine-pool.sh bz1YOURADDRESS              # pool mine
set -euo pipefail

VERSION="${VERSION:-latest}"
REPO="${REPO:-Rexemre/blockzero-core}"
APP_DIR="${APP_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.blockzero/bin}"
DATA_DIR="${DATA_DIR:-$HOME/.blockzero-mainnet}"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

say()  { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- platform guard ----------
[ "$(uname -s)" = "Darwin" ] || die "This installer is for macOS. On Linux build from source or use mine-pool.sh."
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || die "Prebuilt macOS build is Apple Silicon only (got $ARCH). Intel Macs: build from source (doc/build-osx.md)."

# ---------- stop a running node before replacing binaries ----------
stop_node() {
    pgrep -x bitcoind >/dev/null 2>&1 || return 0
    say "Stopping running bitcoind (required before updating binaries)..."
    if [ -x "$BIN_DIR/bitcoin-cli" ]; then
        "$BIN_DIR/bitcoin-cli" -datadir="$DATA_DIR" -rpcport=8332 stop >/dev/null 2>&1 || true
        sleep 5
    fi
    pkill -x bitcoind >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do pgrep -x bitcoind >/dev/null 2>&1 || break; sleep 2; done
}

# ---------- resolve release asset ----------
asset_url() {
    local api
    if [ "$VERSION" = "latest" ]; then
        api="https://api.github.com/repos/$REPO/releases/latest"
    else
        api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
    fi
    curl -fsSL "$api" \
        | grep -o "\"browser_download_url\": *\"[^\"]*macos-arm64\.tar\.gz\"" \
        | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/'
}

# ---------- mainnet config ----------
ensure_config() {
    mkdir -p "$DATA_DIR"
    local conf="$DATA_DIR/bitcoin.conf"
    if [ -f "$conf" ]; then
        if grep -q "addnode=217.160.46.61:8210" "$conf"; then
            say "Mainnet config OK: $conf"
        else
            printf '\naddnode=217.160.46.61:8210\n' >> "$conf"
            say "Added seed node to existing config: $conf"
        fi
        return
    fi
    cat > "$conf" <<'EOF'
# Block Zero mainnet
server=1

[main]
listen=1
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=8332
addnode=217.160.46.61:8210
EOF
    say "Created mainnet config: $conf"
}

say "Block Zero macOS installer"
say "App dir: $APP_DIR"
say "Tools:   $BIN_DIR"
say ""

if [ -d "$APP_DIR/Block Zero.app" ] && [ -x "$BIN_DIR/bitcoin-cli" ] && [ "$FORCE" -eq 0 ]; then
    say "Already installed. Use --force to re-download."
else
    stop_node
    url="$(asset_url)"
    [ -n "$url" ] || die "No macos-arm64 release tarball found in $REPO ($VERSION)."
    name="$(basename "$url")"
    say "Downloading $name ..."
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$name" "$url"
    tar -xzf "$tmp/$name" -C "$tmp"
    src="$(find "$tmp" -maxdepth 1 -type d -name 'blockzero-*-macos-*' | head -n1)"
    [ -n "$src" ] || die "Unexpected release layout (no blockzero-*-macos-* dir)."

    # GUI wallet (.app) — prefer the branded Block Zero.app, fall back to bitcoin-qt.app.
    mkdir -p "$APP_DIR"
    app_src="$(find "$src" -maxdepth 1 -type d -name '*.app' | head -n1)"
    if [ -n "$app_src" ]; then
        rm -rf "$APP_DIR/Block Zero.app"
        cp -R "$app_src" "$APP_DIR/Block Zero.app"
        # Remove the quarantine flag so Gatekeeper does not block first launch.
        xattr -dr com.apple.quarantine "$APP_DIR/Block Zero.app" 2>/dev/null || true
        # Self-heal: older releases shipped the .app without re-signing after
        # macdeployqt, so its signature is invalid and macOS calls it "damaged"
        # and refuses to launch (esp. on Apple Silicon). An ad-hoc re-sign makes
        # it runnable again. (Notarized releases already verify, so this is a
        # harmless no-op there.)
        if ! codesign --verify --deep --strict "$APP_DIR/Block Zero.app" >/dev/null 2>&1; then
            say "Repairing app signature (ad-hoc re-sign)..."
            codesign --force --deep --sign - "$APP_DIR/Block Zero.app" >/dev/null 2>&1 \
                || say "  (re-sign failed; if the app won't open, install Xcode CLT: xcode-select --install)"
        fi
        say "Installed GUI wallet: $APP_DIR/Block Zero.app"
    else
        say "Note: release has no .app bundle; GUI binary will be in $BIN_DIR (run ./bitcoin-qt)."
    fi

    # Command-line tools (bitcoind, bitcoin-cli, and bitcoin-qt if shipped raw).
    mkdir -p "$BIN_DIR"
    if [ -d "$src/bin" ]; then
        cp "$src/bin/"* "$BIN_DIR/" 2>/dev/null || true
        chmod +x "$BIN_DIR/"* 2>/dev/null || true
        xattr -dr com.apple.quarantine "$BIN_DIR" 2>/dev/null || true
        # Re-sign ad-hoc if a tool's signature is invalid (same "damaged"/killed
        # cause as the .app). Harmless on properly signed binaries.
        for tool in "$BIN_DIR"/*; do
            [ -f "$tool" ] || continue
            codesign --verify "$tool" >/dev/null 2>&1 || codesign --force --sign - "$tool" >/dev/null 2>&1 || true
        done
    fi
    rm -rf "$tmp"
    say "Installed tools to $BIN_DIR"
fi

ensure_config

say ""
say "Wallet GUI:"
if [ -d "$APP_DIR/Block Zero.app" ]; then
    say "  open \"$APP_DIR/Block Zero.app\""
else
    say "  $BIN_DIR/bitcoin-qt -datadir=$DATA_DIR"
fi
say "  (uses $DATA_DIR automatically)"
say ""
say "Add $BIN_DIR to your PATH to use bitcoin-cli / bitcoind from anywhere:"
say "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
say ""
say "Pool mine:"
say "  ./mine-pool.sh bz1YOURADDRESS"
say ""
