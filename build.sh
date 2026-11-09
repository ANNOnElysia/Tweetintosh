#!/usr/bin/env bash
set -e

# Base directories
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$BASE_DIR/src"
FINAL_APP_DIR="$BASE_DIR/Tweetintosh.app"
# The new app is assembled here and swapped in at the end. The Dock and Finder remember a missing app's icon, so the
# real bundle must never be gone for longer than the swap takes.
APP_DIR="$BASE_DIR/.build/staging/Tweetintosh.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building Tweetintosh (Headless Native Swift & SwiftUI) ==="

# 1. Compile Release Binary using Swift Package Manager
echo "-> Compiling optimized native binary with SPM..."
cd "$BASE_DIR"
swift build -c release

# 2. Assemble the new app bundle
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "-> Packaging binary..."
cp "$BASE_DIR/.build/release/Tweetintosh" "$MACOS_DIR/Tweetintosh"
strip "$MACOS_DIR/Tweetintosh"

# SwiftPM records the deployment target (15.0) as the SDK the binary was built with, and macOS draws an app's system
# controls in the style of that SDK: switches, sliders and pop-ups came out as Sequoia's, without Liquid Glass. Record
# the SDK actually used, so the app gets the current system's controls.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
MIN_VERSION="$(vtool -show-build "$MACOS_DIR/Tweetintosh" | awk '/minos/ { print $2; exit }')"
if [ -n "$SDK_VERSION" ] && [ -n "$MIN_VERSION" ]; then
    echo "-> Marking the binary as built with the macOS $SDK_VERSION SDK..."
    vtool -set-build-version macos "$MIN_VERSION" "$SDK_VERSION" -replace \
        -output "$MACOS_DIR/Tweetintosh.tmp" "$MACOS_DIR/Tweetintosh"
    mv "$MACOS_DIR/Tweetintosh.tmp" "$MACOS_DIR/Tweetintosh"
else
    echo "warning: could not read the SDK version; the app will get the system controls of macOS $MIN_VERSION" >&2
fi

# 3. Copy resources into app bundle
echo "-> Packaging resources & Info.plist..."
cp "$SRC_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$SRC_DIR/AppIcon.icns" ]; then
    cp "$SRC_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 4. Remove extended attributes & Ad-hoc codesign
echo "-> Clearing extended attributes and signing bundle..."
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# 5. Verify signature
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# 6. Swap the new app in and have macOS re-read it (the icon included)
OLD_APP_DIR="$BASE_DIR/.build/staging/Tweetintosh.old.app"
rm -rf "$OLD_APP_DIR"
[ -d "$FINAL_APP_DIR" ] && mv "$FINAL_APP_DIR" "$OLD_APP_DIR"
mv "$APP_DIR" "$FINAL_APP_DIR"
touch "$FINAL_APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$FINAL_APP_DIR"

# 7. Clean intermediate SPM build cache to keep local disk clean
echo "-> Cleaning intermediate SPM build cache..."
rm -rf "$BASE_DIR/.build"

echo "=== Build succeeded! ==="
echo "Application created at: $FINAL_APP_DIR"
ls -lh "$FINAL_APP_DIR/Contents/MacOS/Tweetintosh"
