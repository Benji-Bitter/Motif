#!/usr/bin/env bash
# Packages build/Motif.app into build/Motif.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Motif.app"
DMG="build/Motif.dmg"

[[ -d "$APP" ]] || { echo "error: $APP missing — run Scripts/build_app.sh first" >&2; exit 1; }

echo "▸ Creating $DMG…"
rm -f "$DMG"
hdiutil create -volname "Motif" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "✓ $DMG"
