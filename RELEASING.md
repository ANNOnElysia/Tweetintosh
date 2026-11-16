# Releasing Tweetintosh

Tweetintosh updates itself with [Sparkle 2](https://sparkle-project.org). Releases stay on GitHub Releases; the app
learns about them from `appcast.xml` on the `main` branch:

    https://raw.githubusercontent.com/ANNOnElysia/Tweetintosh/main/appcast.xml

Each DMG is signed with an EdDSA key. The app holds the public half (`SUPublicEDKey` in `src/Info.plist`) and installs
an update only if its signature matches. The private half stays in the Keychain of whoever makes Sparkle releases;
GitHub Actions does not receive it.

## Once: the signing key

    swift package resolve
    .build/artifacts/sparkle/Sparkle/bin/generate_keys

This stores the private key in your login Keychain and prints the public key. Put the public key in `src/Info.plist`
as `SUPublicEDKey`. Builds without one don't offer updates at all.

Back up the private key and keep it somewhere safe:

    .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key

Without it, no later release can be installed by an existing copy: every user would have to download it by hand.
Never commit it.

## CI builds and packaging

The [CI workflow](.github/workflows/ci.yml) builds on GitHub's `macos-26` Apple silicon runners with the full
Xcode 26.6 toolchain selected through `DEVELOPER_DIR`. Packages support **arm64 on macOS 15 or later**. Intel and
universal binaries are not produced. The runner architecture and the packaged executable are checked explicitly.

| Trigger | Validation | Download location |
| --- | --- | --- |
| Pull request targeting `main` | Release build, available tests, app and DMG checks | Logs only |
| Merge queue (`merge_group`) | Same checks as a pull request | Logs only |
| Push to `main` | Same checks | Workflow run's **Artifacts** section |
| Manual `workflow_dispatch` | Same checks for the selected ref | Workflow run's **Artifacts** section |
| Push of a `v*` tag | Same checks, plus tag/version agreement | Workflow artifacts and a draft GitHub Release |

Each downloadable artifact contains `Tweetintosh-v<version>-macOS-arm64-adhoc.zip`, the corresponding `.dmg`, and
`SHA256SUMS.txt`. The artifact name also includes the first seven characters of the commit SHA; workflow artifacts
expire after 14 days. Release attachments remain available independently of that retention period.

`src/Info.plist` supplies the application version, build number, minimum OS and release channel. CI checks these
against the assembled app, verifies its executable architecture and ad-hoc signature, and validates both the
extracted ZIP and the app inside the mounted DMG. It also checks the DMG's `/Applications` shortcut. The existing
`build.sh` and `tools/make_dmg.sh` perform compilation and packaging; the binary is compiled once. CI sets
`KEEP_BUILD_DIR=1` to retain SwiftPM build data for a cache keyed by platform, architecture, Xcode and package/source
hashes. Local `./build.sh` still removes `.build` by default. If a SwiftPM test target is added, CI runs it as well.

To request a package without making a release, choose **Actions → CI → Run workflow**, select a ref, and run it.
The equivalent CLI command is:

```sh
gh workflow run ci.yml --ref main
```

### Repository settings

A repository administrator must configure a branch ruleset or branch protection rule for `main`:

1. Require a pull request and the **Build and package (arm64)** status check from GitHub Actions before merging.
2. Require branches to be up to date, or enable the merge queue. The workflow handles `merge_group` events.
3. Apply the rule to administrators and other bypass actors as appropriate for the repository. Do not permit a
   failed or missing check to be bypassed in the normal merge process.
4. Enable Actions and allow the SHA-pinned official `actions/checkout`, `actions/cache`, `actions/upload-artifact`
   and `actions/download-artifact` actions. Retain approval requirements for workflows from outside contributors.

The required job has no path filters or event-level skip conditions, so documentation-only PRs also receive it.
New PR commits trigger another check and cancel the superseded PR run. Do not use commit-message CI-skip directives
on PRs: GitHub can leave required checks pending when a whole workflow is skipped.

The build job has only `contents: read`, does not persist checkout credentials, and uses no signing secrets.
Fork PRs run through `pull_request`, never `pull_request_target`; they cannot enter the Release job. Only that
tag-triggered job receives `contents: write`, downloads the validated artifact from the same workflow run, checks
its checksums, and uploads it without running repository scripts. No personal access token is needed.

### Creating a CI release

1. Through a reviewed PR, set `CFBundleShortVersionString` in `src/Info.plist` to the intended version and increase
   `CFBundleVersion`. Set `TweetintoshUpdateChannel` to `preview` for a Developer Preview; omit it for stable.
2. After the PR merges and CI passes, create and push a tag on that commit, for example:

   ```sh
   git tag v0.1.2
   git push origin v0.1.2
   ```

3. CI rejects a tag that differs from `v<CFBundleShortVersionString>`. After successful build and packaging checks,
   it creates a **draft** GitHub Release with the ZIP, DMG and checksums. A preview channel marks it as a prerelease.
4. Download the draft's DMG, install the app and launch it on a supported Mac. Review the notes and assets before
   publishing the draft. CI packaging checks do not prove the native UI works. A rerun fails if a release for that
   tag already exists; inspect the existing draft rather than overwriting released assets.

These CI packages use the existing **ad-hoc code signature**. They are not Developer ID signed or notarised and
can require user approval in macOS Gatekeeper. Developer ID signing and notarisation need a separate signing setup;
they are not implied by a successful CI run. No Apple certificate, notarisation credential or Sparkle private key
is required for this workflow.

CI does not update `appcast.xml` or create a Sparkle EdDSA signature. Publishing its draft alone therefore does not
offer an automatic update to installed copies. For the signed Sparkle update feed, use the local release procedure
below; its DMG is a separate artifact and must have its own matching signature. If the DMG's bytes change,
regenerate its signature; if the asset name changes, update the feed's download URL.

Before enabling the merge gate, verify a successful PR and an intentional compilation failure followed by a new
passing commit. After merge, download a fresh `main` artifact; then exercise a version tag, confirm a version
mismatch fails before publishing, and check that a failed build/package cannot start the Release job. Check an
outside-contributor PR with the repository's approval policy. Branch protection must actually block the failing PR;
workflow success alone cannot establish that setting.

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
