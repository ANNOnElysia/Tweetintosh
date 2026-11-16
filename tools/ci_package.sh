#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PLIST="$BASE_DIR/src/Info.plist"
APP_PATH="$BASE_DIR/Tweetintosh.app"
DIST_DIR="$BASE_DIR/dist"

fail() {
    echo "error: $*" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

VERSION="$(plist_value "$SOURCE_PLIST" CFBundleShortVersionString)"
if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+)*(-[A-Za-z0-9]+([.-][A-Za-z0-9]+)*)?$ ]]; then
    fail "Unsafe release version: $VERSION"
fi

validate_app() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local key expected actual executable architectures
    [ -d "$app" ] || fail "App bundle is missing: $app"
    [ -f "$plist" ] || fail "App metadata is missing: $plist"
    for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion CFBundleExecutable; do
        expected="$(plist_value "$SOURCE_PLIST" "$key")"
        actual="$(plist_value "$plist" "$key")"
        [ -n "$expected" ] && [ "$actual" = "$expected" ] || fail "$key mismatch in $app (expected '$expected', found '$actual')"
    done
    executable="$(plist_value "$plist" CFBundleExecutable)"
    case "$executable" in
        ''|.|..|*/*) fail "Unsafe bundle executable: $executable" ;;
    esac
    [ -x "$app/Contents/MacOS/$executable" ] || fail "App executable is missing or not executable: $app"
    architectures="$(lipo -archs "$app/Contents/MacOS/$executable")"
    [ "$architectures" = arm64 ] || fail "Expected arm64 executable in $app; found '$architectures'"
    [ -d "$app/Contents/Frameworks/Sparkle.framework" ] || fail "Embedded Sparkle.framework is missing: $app"
    [ -f "$app/Contents/Frameworks/Sparkle.framework/Sparkle" ] || fail "Embedded Sparkle binary is missing: $app"
    codesign --verify --deep --strict --verbose=2 "$app"
}

# Reject missing or stale bundles before make_dmg.sh can invoke its build fallback.
validate_app "$APP_PATH"

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tweetintosh-ci.XXXXXX")"
MOUNT_DIR="$VALIDATION_DIR/mount"
MOUNT_ATTEMPTED=0
cleanup() {
    local status=$?
    trap - EXIT
    if [ "$MOUNT_ATTEMPTED" = 1 ]; then
        if ! hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
            if ! hdiutil detach -force "$MOUNT_DIR" >/dev/null 2>&1; then
                echo "error: Could not detach validation image at $MOUNT_DIR; preserving its mount directory" >&2
                exit 1
            fi
        fi
    fi
    rm -rf "$VALIDATION_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$DIST_DIR" "$MOUNT_DIR" "$VALIDATION_DIR/zip"
ARTIFACT_BASE="Tweetintosh-v${VERSION}-macOS-arm64-adhoc"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASE.dmg"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASE.zip"

bash "$BASE_DIR/tools/make_dmg.sh"
mv "$BASE_DIR/Tweetintosh-v${VERSION}.dmg" "$DMG_PATH"
hdiutil verify "$DMG_PATH"
MOUNT_ATTEMPTED=1
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH"
validate_app "$MOUNT_DIR/Tweetintosh.app"
[ -L "$MOUNT_DIR/Applications" ] || fail "DMG Applications link is missing"
[ "$(readlink "$MOUNT_DIR/Applications")" = /Applications ] || fail "DMG Applications link must target /Applications"
hdiutil detach "$MOUNT_DIR"
MOUNT_ATTEMPTED=0

# Remove an earlier ZIP so ditto cannot retain obsolete archive entries.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$VALIDATION_DIR/zip"
validate_app "$VALIDATION_DIR/zip/Tweetintosh.app"

(
    cd "$DIST_DIR"
    shasum -a 256 "$ARTIFACT_BASE.zip" "$ARTIFACT_BASE.dmg" > SHA256SUMS.txt
)
echo "Validated release artifacts: $ZIP_PATH and $DMG_PATH"
