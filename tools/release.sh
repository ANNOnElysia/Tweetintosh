#!/usr/bin/env bash
# Builds a release and adds it to the update feed. See RELEASING.md.
#
#   tools/release.sh <version> [--stable] [--notes <notes.md>]
#
# Sets the version in src/Info.plist and raises the build number by one, builds the app and its DMG, signs the DMG with
# the Sparkle key in your Keychain, and adds the release to appcast.xml. It uploads and pushes nothing: the last lines
# say what to publish, and in which order.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$BASE_DIR/src/Info.plist"
APPCAST="$BASE_DIR/appcast.xml"
REPO_URL="https://github.com/ANNOnElysia/Tweetintosh"
buddy() { /usr/libexec/PlistBuddy "$@"; }

VERSION="${1:-}"
shift || true
CHANNEL="preview"
NOTES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --stable) CHANNEL="" ;;
        --notes) NOTES="$2"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ -z "$VERSION" ]; then
    echo "usage: tools/release.sh <version> [--stable] [--notes <notes.md>]" >&2
    exit 1
fi
if [ -n "$NOTES" ] && [ ! -f "$NOTES" ]; then
    echo "Release notes not found: $NOTES" >&2
    exit 1
fi
if [ -z "$(buddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null)" ]; then
    echo "src/Info.plist has no SUPublicEDKey yet: create the signing key first (RELEASING.md, Once)." >&2
    exit 1
fi

OLD_VERSION="$(buddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
OLD_BUILD="$(buddy -c 'Print :CFBundleVersion' "$PLIST")"
# Sparkle orders releases by build number, so each release needs a higher one than every release before it
BUILD=$((OLD_BUILD + 1))
TAG="v$VERSION"
DMG="$BASE_DIR/Tweetintosh-$TAG.dmg"

echo "=== Releasing Tweetintosh $VERSION (build $BUILD, ${CHANNEL:-stable} channel; was $OLD_VERSION build $OLD_BUILD) ==="
buddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
buddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
# A preview build also takes later previews; a stable build takes only stable releases
buddy -c "Delete :TweetintoshUpdateChannel" "$PLIST" 2>/dev/null || true
if [ -n "$CHANNEL" ]; then
    buddy -c "Add :TweetintoshUpdateChannel string $CHANNEL" "$PLIST"
fi

"$BASE_DIR/build.sh"
"$BASE_DIR/tools/make_dmg.sh"

# build.sh clears .build, Sparkle's tools included; resolving brings them back from SwiftPM's cache
(cd "$BASE_DIR" && swift package resolve >/dev/null)
SIGN_UPDATE="$BASE_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
echo "-> Signing the DMG (macOS may ask to let sign_update use the key in your Keychain)..."
SIGNATURE="$("$SIGN_UPDATE" "$DMG")"

APP="$BASE_DIR/Tweetintosh.app"
MIN_SYSTEM="$(buddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Tweetintosh")"

python3 - "$APPCAST" "$VERSION" "$BUILD" "$CHANNEL" "$MIN_SYSTEM" "$ARCHS" "$SIGNATURE" \
    "$REPO_URL/releases/download/$TAG/$(basename "$DMG")" "$REPO_URL/releases/tag/$TAG" "$NOTES" <<'PY'
import sys, email.utils, html
appcast, version, build, channel, min_system, archs, signature, url, page, notes = sys.argv[1:]
feed = open(appcast).read()
if f"<sparkle:version>{build}</sparkle:version>" in feed:
    sys.exit(f"appcast.xml already has build {build}")
lines = [
    "        <item>",
    f"            <title>Tweetintosh {html.escape(version)}</title>",
    f"            <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>",
    f"            <sparkle:version>{build}</sparkle:version>",
    f"            <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>",
    f"            <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>",
]
# Macs that can't run every slice of the binary aren't offered the release
if archs.split() == ["arm64"]:
    lines.append("            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>")
if channel:
    lines.append(f"            <sparkle:channel>{channel}</sparkle:channel>")
lines.append(f"            <link>{page}</link>")
if notes:
    text = open(notes).read().replace("]]>", "]]]]><![CDATA[>")
    lines.append(f'            <description sparkle:format="markdown"><![CDATA[{text}]]></description>')
lines.append(f'            <enclosure url="{url}" type="application/octet-stream" {signature} />')
lines.append("        </item>")
marker = "<!-- Releases, newest first -->"
feed = feed.replace(marker, marker + "\n" + "\n".join(lines), 1)
open(appcast, "w").write(feed)
PY

echo
echo "=== Built $(basename "$DMG") and added it to appcast.xml ==="
echo "Publish in this order, so the feed never points at a file that isn't there yet:"
echo "  1. Create the release $TAG at $REPO_URL/releases/new${CHANNEL:+ (tick \"Set as a pre-release\")}"
echo "     and attach $(basename "$DMG")."
echo "  2. Commit src/Info.plist and appcast.xml, and merge them into main."
echo "Installed copies see the update the next time they check."
