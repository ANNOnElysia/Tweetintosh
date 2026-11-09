# AGENTS.md

A native macOS client for X, in plain SwiftUI + AppKit. There is no web view in the main UI: credentials are captured
once from a throwaway `WKWebView` (`LoginWindowController`), then everything is drawn natively from X's private
GraphQL/REST endpoints, which `APIClient` talks to directly.

## Build and run

No Xcode project: this is a Swift Package plus a packaging script. It does need Xcode's toolchain, though, not just the
Command Line Tools: the shared state uses the Observation framework (`@Observable`, `@State`, `@Bindable`), whose
macros the Command Line Tools cannot expand. Select Xcode with `sudo xcode-select -s <path to Xcode.app>`
(on this machine `~/Xcode/Xcode-beta.app`) and check with `xcode-select -p`.

```sh
swift build -c release      # compile check, ~50 s
./build.sh                  # release build → Tweetintosh.app → ad-hoc codesign, then deletes .build
open Tweetintosh.app        # run
```

The app icon is drawn in code: `swift tools/make-app-icon.swift` rewrites `src/AppIcon.icns`. Change the drawing there
rather than editing the `.icns` by hand.

`build.sh` removes `.build` at the end, so a `swift build` after it is always a full rebuild.

Runtime state lives in `~/Library/Application Support/Tweetintosh/` (accounts, credentials, timeline and
notification caches) and in `UserDefaults` under `com.anno.tweetintosh`. Deleting the data folder plus the defaults
domain reproduces a fresh install.

## Source map

Entry point and shell
- `main.swift` — `@main` AppDelegate: windows, menu bar, settings window, login flow, account switching, fn+Control
  window tiling.
- `AppRootView.swift` — root layout: top capsule / tab bar, sidebar with feeds and notification filters, the overlay
  page stack, sheets, and all the global overlays (toasts, lightboxes, peek).
- `NavigationManager.swift` — global navigation state: `AppTab`, the `OverlayPage` stack, compose and reply sheet
  state, search state.

Feeds and posts
- `TimelineView.swift`, `TimelineViewModel.swift` — home feeds (For You / Following / Lists), the floating
  "N new posts" pill, pull-to-refresh, cursor pagination.
- `TimelineTableView.swift` — the Home timeline as an NSTableView with reused NSHostingView cells and cached row heights.
  A spike behind `Tweetintosh_TimelineUsesTable` (default on); `false` goes back to the List in `TimelineView.swift`.
- `TweetRowView.swift`, `TweetText.swift`, `QuotedTweetCard.swift` — a post row, its text and entities, quoted posts.
- `TimelineCacheManager.swift` — the offline snapshot that makes launch instant.

Post page
- `TweetDetailView.swift`, `TweetDetailViewModel.swift` — the post page: ancestors, replies grouped into threads,
  quick reply dock, pull-to-refresh.
- `DetailPane.swift` — the post pane beside the timeline in wide windows, and the column layout around it.
- `Preloading.swift`, `PeekPreview.swift` — hover prefetch and the deep-press peek card.

Other screens
- `ProfileView.swift`, `ProfileAPI.swift` — profiles and their tabs; `GraphQLOperationIDs` lives in `ProfileAPI.swift`
  and discovers/repairs stale GraphQL operation ids at runtime.
- `NotificationsView.swift`, `NotificationsViewModel.swift` — notifications: X's All, Priority (people you follow) and
  Mentions feeds, fetched separately.
- `SearchView.swift`, `SearchAPI.swift`, `SearchSuggestions.swift` — search, typeahead, recent searches.
- `Article.swift`, `ArticleReaderView.swift` — X Articles rendered natively.
- `VideosFeed.swift`, `VideosView.swift` — the Videos tab: X's immersive video feed (`ImmersiveMedia`), one video to
  a page, with paging scroll, keyboard and the action rail. Its player is `AutoplayVideoView`, with sound and pausing.
  It downloads the next few videos ahead, keeps the pages either side paused on their first frame, and pages a finger
  itself (`TouchPaging`); double-tap likes. The tab is off by default and turned on in Settings
  (`ThemeManager.showVideosTab`); `AppTab.available` lists the tabs on offer.
- `PressDragSelection.swift` — capsule tab bars that select on press and follow a drag.
- `ListSupport.swift` — X Lists, and the shared helpers for hosting scrolling screens in a SwiftUI `List`.

Media
- `ImageGridView.swift`, `ImageLightboxView.swift`, `VideoLightboxView.swift` — 1–4 image layouts, photo viewer,
  native AVPlayer with quality and subtitles.
- `AutoplayVideo.swift` — muted, looping playback of videos and GIFs in place on the timeline.
- `ComposerMedia.swift` — the attach button, thumbnails, and upload shared by the post and reply composers.
- `MediaCacheManager.swift`, `MediaActions.swift`, `MediaAttachments.swift` — memory/disk image cache, save/copy/open
  actions, attachment parsing.

Platform
- `ThemeManager.swift` — appearance (dark / rice white / system), accent colours, typefaces, Liquid Glass styling.
- `Localization.swift` — the translation table for English, 日本語, 한국어, 简体中文, 繁體中文.
- `Accounts.swift`, `AuthCredentials.swift`, `LoginWindowController.swift` — multi-account storage and headless
  credential capture.
- `WebKitWriteChannel.swift` — the hidden web view every request that changes something on X goes through.
- `XFailures.swift` — what X's numeric refusal codes mean, and how to say it in the reader's language.
- `Engagement.swift` — shared engagement rules: blocked authors, rejection reporting, keeping every on-screen copy of
  a post in sync after a like / repost / bookmark.
- `ObservationSupport.swift` — `observeChanges(of:perform:)`, the stand-in for subscribing to `objectWillChange` on an
  `@Observable` object from AppKit code.
- `TouchSupport.swift` — touch screens (macOS 27): `ScrollInput` tells a finger's scroll from a trackpad's, and the
  app's `.target` button style gives every borderless button a rectangular target of at least 36 points.

## Conventions

- **Comments explain why, not what**, and are written in full sentences. Match the surrounding density; most
  non-obvious behaviour in this codebase already carries a short rationale.
- **Every user-facing string is localised.** Add a key to the table in `Localization.swift` with all five languages,
  read it with `LocalizationManager.shared.t("key")` or `.format("key", ["n": …])` with `{n}` placeholders. A key
  missing a language silently falls back to English.
- **Colours, fonts and glass come from `ThemeManager`**, never hard-coded, so the three appearances and the accent
  choices keep working. Glass surfaces go through the shared `.glassEffect` / `AdaptiveGlassModifier` helpers and
  respect Reduce Transparency.
- **Liquid Glass APIs are macOS 26+**; guard them with `if #available(macOS 26.0, *)` and give older systems the
  existing fallback material.
- **Scrolling screens are SwiftUI `List`s**, not `ScrollView` + `LazyVStack` (see the header of `ListSupport.swift`
  for what that costs and the helpers that absorb it). The one exception is the Videos tab (`VideosView.swift`): a
  `List` cannot snap to whole pages, so it is a `ScrollView` with `.scrollTargetBehavior(.paging)`; its pages are
  screen-sized and few, so the costs a `List` avoids don't arise there.
- **Borderless buttons use `.buttonStyle(.target)`**, never `.plain`: a plain button only answers inside its own frame,
  which for an icon is far too small for a finger. Test touch with an iPad on iPadOS 27 over Sidecar; a finger's drag
  reaches a scroll view whose touch scrolling is off as a mouse drag, and never reaches event monitors as a touch.
- **Shared state is moving to `@Observable`.** `NavigationManager` and `TimelineViewModel` are already observed per
  property, so a view refreshes only for what its `body` reads: read them as plain `let` properties (`@Bindable` where a
  `$binding` is needed), mark bookkeeping that no view shows `@ObservationIgnored`, and from AppKit code watch them with
  `observeChanges(of:perform:)`. The other classes are still `ObservableObject`.
- **Every on-screen copy of a post must stay in sync** after an engagement action: go through `Engagement` rather
  than mutating one view model.
- **Reads use `URLSession`; writes go through `WebKitWriteChannel`.** X silently drops writes that do not arrive
  over a browser's connection — the same CreateTweet from `URLSession` answers `200` with an empty `tweet_results`
  and publishes nothing — so anything that changes state on X must be sent from inside the hidden web view. Do not
  "simplify" a mutation back to `URLSession`.
- **Strict Apple HIG compliance**: All UI, interactions, typography, layout, animations, and controls must strictly adhere to Apple's Human Interface Guidelines (HIG) for macOS. If there is any uncertainty or ambiguity, research official HIG guidelines or ask the user for clarification.
- Build after touching a shared type — `swift build -c release` — before claiming anything works. There is no test
  target, so verification is a compile plus a run.

## Commits

Conventional commits, lowercase, imperative, scoped by area: `feat(detail):`, `fix(theme):`, `refactor(glass):`,
`chore(repo):`. The subject says what changed; the body says why it was needed and what the user now sees, wrapped at
120 columns. One logical change per commit, and keep it compiling.

Whenever the user reviews and approves changes ("通过"), immediately commit them to git following this format.

## Known state

- `DebugSupport.swift` holds temporary scaffolding for the reply-threading work: set `MAX_DEBUG_DETAIL=1` in the
  environment to have the app open a busy post on launch and log how X's replies were grouped. It is inert otherwise.
  Delete the file and its two call sites once that work settles.
- ImmersiveMedia's paging: X's own client sends the same request again (same `pinned_tweet_id`, no cursor) for each
  further batch, and each answer is a new set of videos; the `cursor-bottom` it returns is never used. Its query id
  lives in the on-demand chunk `bundle.ImmersiveMediaViewer`, which `GraphQLOperationIDs` locates from the page's
  inline chunk map.
- The Messages tab is a placeholder (`NewDestinationPlaceholderView`); X's DMs are not implemented.
- Bookmarks is a Home feed (sidebar, ⌥E), fetched with X's `Bookmarks` GraphQL operation; lists have no shortcut.
