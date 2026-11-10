# Releasing Tweetintosh

Tweetintosh updates itself with [Sparkle 2](https://sparkle-project.org). Releases stay on GitHub Releases; the app
learns about them from `appcast.xml` on the `main` branch:

    https://raw.githubusercontent.com/ANNOnElysia/Tweetintosh/main/appcast.xml

Each DMG is signed with an EdDSA key. The app holds the public half (`SUPublicEDKey` in `src/Info.plist`) and installs
an update only if its signature matches. The private half stays in the Keychain of whoever makes releases.

## Once: the signing key

    swift package resolve
    .build/artifacts/sparkle/Sparkle/bin/generate_keys

This stores the private key in your login Keychain and prints the public key. Put the public key in `src/Info.plist`
as `SUPublicEDKey`. Builds without one don't offer updates at all.

Back up the private key and keep it somewhere safe:

    .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key

Without it, no later release can be installed by an existing copy: every user would have to download it by hand.
Never commit it.

## Each release

    tools/release.sh 0.2.0 --notes notes.md

- Sets `CFBundleShortVersionString` to the version given and raises `CFBundleVersion` by one. Sparkle orders releases
  by build number, so a copy is never offered anything older than itself.
- Builds `Tweetintosh.app` and `Tweetintosh-v0.2.0.dmg`, signs the DMG and adds the release to `appcast.xml`. The
  entry records the minimum macOS (`LSMinimumSystemVersion`) and, for an Apple silicon-only build, `arm64`, so Macs
  that can't run it aren't offered it.
- `--notes` takes a Markdown file. Sparkle shows it under the version in the update window.

Then publish, in this order, so the feed never points at a file that isn't there yet:

1. Create the release `v0.2.0` on GitHub and attach the DMG.
2. Commit `src/Info.plist` and `appcast.xml` and merge them into `main`.

Installed copies find the update on their next check (daily, or Check for Updates… in the app menu).

## Developer Preview and stable releases

Releases are Developer Previews unless `--stable` is given:

- A preview release is marked with the `preview` channel in the feed and as a pre-release on GitHub.
- A preview build (`TweetintoshUpdateChannel` = `preview` in `Info.plist`) takes preview and stable releases.
- A stable build takes stable releases only.

Once a stable release is out, a preview installation that updates to it becomes a stable one and stops seeing
previews.

## What an update keeps

Accounts, sign-ins, settings and caches live outside the app, in `~/Library/Application Support/Tweetintosh` and the
app's defaults (`com.anno.tweetintosh`). An update replaces only the app, so all of it carries over. A failed
download or a bad signature leaves the installed app as it was.
