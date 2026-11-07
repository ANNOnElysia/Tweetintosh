#!/usr/bin/env bash
set -e

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VOLNAME="Tweetintosh"
DMG_FINAL="$BASE_DIR/Tweetintosh-v0.1.0.dmg"
DMG_TEMP="/tmp/tweetintosh_rw.dmg"
BG_IMG="$BASE_DIR/site/dmg_background.png"
APP_SRC="$BASE_DIR/Tweetintosh.app"
STAGE_DIR="/tmp/tweetintosh_stage"

if [ ! -d "$APP_SRC" ]; then
    echo "Tweetintosh.app not found! Building first..."
    "$BASE_DIR/build.sh"
fi

echo "=== Packaging Styled DMG for Tweetintosh ==="
rm -rf "$STAGE_DIR" "$DMG_TEMP" "$DMG_FINAL"
mkdir -p "$STAGE_DIR/.background"

# 1. Prepare staging
cp -R "$APP_SRC" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$BG_IMG" "$STAGE_DIR/.background/background.png"

# 2. Create read-write disk image
hdiutil create -srcfolder "$STAGE_DIR" -volname "$VOLNAME" -fs HFS+ -format UDRW -ov "$DMG_TEMP"
rm -rf "$STAGE_DIR"

# 3. Mount read-write
ATTACH_OUT=$(hdiutil attach -readwrite -nobrowse -noautoopen "$DMG_TEMP")
DEVICE=$(echo "$ATTACH_OUT" | head -n 1 | awk '{print $1}')

# 4. Configure Finder appearance via AppleScript
osascript << APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 150, 960, 550}
    
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    
    set position of item "Tweetintosh.app" of container window to {160, 195}
    set position of item "Applications" of container window to {500, 195}
    
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# 5. Detach and convert
sync
hdiutil detach "$DEVICE"
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TEMP"

echo "=== Styled DMG generated successfully! ==="
ls -lh "$DMG_FINAL"
