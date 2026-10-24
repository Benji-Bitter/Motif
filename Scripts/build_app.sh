#!/usr/bin/env bash
# Builds Motif as a universal (arm64 + x86_64) .app bundle.
#
#   Scripts/build_app.sh [debug|release]
#
# Output: build/Motif.app — unsigned (ad-hoc signed for local execution).
# For distribution, sign with a Developer ID and notarise — see
# Documentation/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APPDIR="build/Motif.app"

echo "▸ Building Motif ($CONFIG, universal)…"
swift build -c "$CONFIG" --arch arm64 --arch x86_64

# Universal products land under .build/apple/Products/<config>.
case "$CONFIG" in
    debug|Debug)   CONFIG_NAME=Debug ;;
    release|Release) CONFIG_NAME=Release ;;
    *) CONFIG_NAME="$CONFIG" ;;
esac
PRODUCT_DIR=".build/apple/Products/$CONFIG_NAME"
BIN="$PRODUCT_DIR/Motif"
if [[ ! -f "$BIN" ]]; then
    # Fall back to single-arch layout (e.g. when only one arch was built).
    PRODUCT_DIR="$(find .build -type d -name "$CONFIG_NAME" -path "*/Products/*" | head -1)"
    BIN="$PRODUCT_DIR/Motif"
fi
[[ -f "$BIN" ]] || { echo "error: built binary not found" >&2; exit 1; }

echo "▸ Assembling $APPDIR…"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN" "$APPDIR/Contents/MacOS/Motif"
cp Resources/Info.plist "$APPDIR/Contents/Info.plist"
printf 'APPL????' > "$APPDIR/Contents/PkgInfo"

# SPM resource bundle (if any resources exist).
BUNDLE="$(find "$PRODUCT_DIR" -maxdepth 1 -name 'Motif_Motif.bundle' | head -1)"
if [[ -n "$BUNDLE" ]]; then
    cp -R "$BUNDLE" "$APPDIR/Contents/Resources/"
fi

# App icon if one has been generated (Scripts/generate_icon.swift).
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APPDIR/Contents/Resources/"
fi

# Ad-hoc sign so the binary launches locally on Apple Silicon.
codesign --force --sign - --timestamp=none "$APPDIR" 2>/dev/null || true

echo "✓ $APPDIR"
file "$APPDIR/Contents/MacOS/Motif" | sed 's/^/  /'
