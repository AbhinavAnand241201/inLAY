#!/usr/bin/env bash
#
# Inlay CLI installer — builds `inlay` from source and drops it on your PATH.
# No Homebrew tap required.
#
#   curl -fsSL https://raw.githubusercontent.com/AbhinavAnand241201/inLAY/main/cli/install.sh | bash
#
# Override the ref (branch/tag) or install dir:
#   INLAY_REF=v0.1.0 INLAY_BIN=/usr/local/bin curl -fsSL …/install.sh | bash
#
set -euo pipefail

REPO="AbhinavAnand241201/inLAY"
REF="${INLAY_REF:-main}"

say() { printf '\033[36m%s\033[0m\n' "$*"; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

command -v swift >/dev/null 2>&1 || {
  err "Swift toolchain not found. Install Xcode (or the Command Line Tools: xcode-select --install) and retry."
  exit 1
}

# Choose a writable bin dir already on PATH (override with INLAY_BIN).
BIN="${INLAY_BIN:-}"
if [ -z "$BIN" ]; then
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
    if [ -d "$d" ] && [ -w "$d" ]; then BIN="$d"; break; fi
  done
fi
BIN="${BIN:-$HOME/.local/bin}"
mkdir -p "$BIN"

say "Installing inlay from $REPO@$REF …"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" \
  | tar xz -C "$TMP" 2>/dev/null \
  || curl -fsSL "https://github.com/$REPO/archive/refs/tags/$REF.tar.gz" | tar xz -C "$TMP"

SRC="$(find "$TMP" -maxdepth 1 -type d -name 'inLAY-*' | head -1)"
[ -n "$SRC" ] || { err "Couldn't unpack the source."; exit 1; }

say "Building (release) … this takes ~20s the first time."
( cd "$SRC/cli" && swift build -c release >/dev/null )

# Keep the binary next to its SwiftPM resource bundle (registry.json), then
# symlink it onto PATH. The CLI also falls back to the CDN if the bundle moves.
PREFIX="${INLAY_PREFIX:-$HOME/.inlay}"
rm -rf "$PREFIX/libexec"
mkdir -p "$PREFIX/libexec"
cp "$SRC/cli/.build/release/inlay" "$PREFIX/libexec/inlay"
cp -R "$SRC/cli/.build/release/inlay_inlay.bundle" "$PREFIX/libexec/" 2>/dev/null || true
ln -sf "$PREFIX/libexec/inlay" "$BIN/inlay"
say "✓ Installed inlay → $BIN/inlay  (resources in $PREFIX/libexec)"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) err "Note: $BIN is not on your PATH. Add it, e.g.:  echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.zshrc" ;;
esac

"$BIN/inlay" --version >/dev/null 2>&1 && say "Run 'inlay list' to see all components."
