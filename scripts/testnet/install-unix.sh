#!/usr/bin/env bash
# Install Block Zero testnet binaries on Linux or macOS from GitHub Releases.
# Usage: ./install-unix.sh [version-tag|latest]

set -euo pipefail

VERSION="${1:-latest}"
REPO="Rexemre/blockzero-core"
INSTALL_DIR="${BZERO_INSTALL_DIR:-${HOME}/.local/share/blockzero}"
BIN_DIR="${INSTALL_DIR}/bin"
DATA_DIR="${HOME}/.blockzero/testnet3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux)  PATTERN="linux-${ARCH}" ;;
  darwin) PATTERN="macos-${ARCH}" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

mkdir -p "$BIN_DIR" "$DATA_DIR"

if [[ -x "${BIN_DIR}/bitcoind" && -x "${BIN_DIR}/bitcoin-cli" ]]; then
  echo "Binaries already in ${BIN_DIR}"
else
  if [[ "$VERSION" == "latest" ]]; then
    API="https://api.github.com/repos/${REPO}/releases/latest"
  else
    API="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
  fi
  URL="$(curl -fsSL "$API" | grep -o "https://[^\"]*${PATTERN}[^\"]*\\.tar\\.gz" | head -1 || true)"
  if [[ -z "$URL" ]]; then
    echo "No release tarball matching ${PATTERN} found."
    echo "Build from source: https://github.com/${REPO} (see doc/build-unix.md)"
    exit 1
  fi
  TMP="$(mktemp -d)"
  echo "Downloading $(basename "$URL")..."
  curl -fsSL "$URL" | tar -xz -C "$TMP"
  find "$TMP" -type f \( -name bitcoind -o -name bitcoin-cli \) -exec cp {} "$BIN_DIR/" \;
  chmod +x "${BIN_DIR}/"* 2>/dev/null || true
  rm -rf "$TMP"
  echo "Installed to ${BIN_DIR}"
fi

if [[ ! -f "${DATA_DIR}/bitcoin.conf" ]]; then
  cp "${SCRIPT_DIR}/bitcoin.conf.example" "${DATA_DIR}/bitcoin.conf"
fi

echo ""
echo "Add to PATH:"
echo "  export PATH=\"${BIN_DIR}:\$PATH\""
echo ""
echo "Start mining:"
echo "  BZERO_BINDIR=\"${BIN_DIR}\" ${SCRIPT_DIR}/mine-testnet.sh"
