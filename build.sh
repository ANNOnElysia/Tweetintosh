#!/usr/bin/env bash
set -e

# Base directories
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$BASE_DIR/src"
APP_DIR="$BASE_DIR/Tweetintosh.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building Tweetintosh (Headless Native Swift & SwiftUI) ==="

# 1. Clean previous build directory
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 2. Compile Release Binary using Swift Package Manager
echo "-> Compiling optimized native binary with SPM..."
cd "$BASE_DIR"
swift build -c release

# 3. Copy binary into app bundle
echo "-> Packaging binary..."
cp "$BASE_DIR/.build/release/Tweetintosh" "$MACOS_DIR/Tweetintosh"
strip "$MACOS_DIR/Tweetintosh"

# 4. Copy resources into app bundle
echo "-> Packaging resources & Info.plist..."
cp "$SRC_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$SRC_DIR/AppIcon.icns" ]; then
    cp "$SRC_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 5. Remove extended attributes & Ad-hoc codesign
echo "-> Clearing extended attributes and signing bundle..."
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

# 6. Verify signature
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# 7. Clean intermediate SPM build cache to keep local disk clean
echo "-> Cleaning intermediate SPM build cache..."
rm -rf "$BASE_DIR/.build"

echo "=== Build succeeded! ==="
echo "Application created at: $APP_DIR"
ls -lh "$MACOS_DIR/Tweetintosh"
