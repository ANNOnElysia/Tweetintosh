#!/usr/bin/env bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VOLNAME="Tweetintosh"
DMG_FINAL="$BASE_DIR/Tweetintosh-v0.1.0.dmg"
APP_SRC="$BASE_DIR/Tweetintosh.app"
STAGE_DIR="/tmp/tweetintosh_stage"

if [ ! -d "$APP_SRC" ]; then
    echo "Tweetintosh.app not found! Building first..."
    "$BASE_DIR/build.sh"
fi

echo "=== Packaging Clean Native DMG for Tweetintosh ==="
rm -rf "$STAGE_DIR" "$DMG_FINAL"
mkdir -p "$STAGE_DIR"

# 1. Copy App & Applications Symlink
cp -R "$APP_SRC" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

# 2. Build compressed read-only DMG
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_FINAL"
rm -rf "$STAGE_DIR"

echo "=== Clean DMG generated successfully! ==="
ls -lh "$DMG_FINAL"
