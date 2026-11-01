# AGENTS.md

A native macOS client for X, in plain SwiftUI + AppKit. There is no web view in the main UI: credentials are captured
once from a throwaway `WKWebView` (`LoginWindowController`), then everything is drawn natively from X's private
GraphQL/REST endpoints, which `APIClient` talks to directly.

## Build and run

No Xcode project, no Xcode install needed: this is a Swift Package plus a packaging script.

```sh
swift build -c release      # compile check, ~50 s; warnings about CommandLineTools search paths are harmless
./build.sh                  # release build → Tweetintosh.app → ad-hoc codesign, then deletes .build
open Tweetintosh.app        # run
```

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
- `TweetRowView.swift`, `TweetText.swift`, `QuotedTweetCard.swift` — a post row, its text and entities, quoted posts.
- `TimelineCacheManager.swift` — the offline snapshot that makes launch instant.

Post page
- `TweetDetailView.swift`, `TweetDetailViewModel.swift` — the post page: ancestors, replies grouped into threads,
  quick reply dock, pull-to-refresh.
- `Preloading.swift`, `PeekPreview.swift` — hover prefetch and the deep-press peek card.

Other screens
- `ProfileView.swift`, `ProfileAPI.swift` — profiles and their tabs; `GraphQLOperationIDs` lives in `ProfileAPI.swift`
  and discovers/repairs stale GraphQL operation ids at runtime.
- `NotificationsView.swift`, `NotificationsViewModel.swift`, `NotificationReplies.swift` — notifications, including
  replies and mentions reconstructed by search because X's feed omits them.
- `SearchView.swift`, `SearchAPI.swift`, `SearchSuggestions.swift` — search, typeahead, recent searches.
- `Article.swift`, `ArticleReaderView.swift` — X Articles rendered natively.
- `ListSupport.swift` — X Lists, and the shared helpers for hosting scrolling screens in a SwiftUI `List`.

Media
- `ImageGridView.swift`, `ImageLightboxView.swift`, `VideoLightboxView.swift` — 1–4 image layouts, photo viewer,
  native AVPlayer with quality and subtitles.
- `MediaCacheManager.swift`, `MediaActions.swift`, `MediaAttachments.swift` — memory/disk image cache, save/copy/open
  actions, attachment parsing.

Platform
- `ThemeManager.swift` — appearance (dark / rice white / system), accent colours, typefaces, Liquid Glass styling.
- `Localization.swift` — the translation table for English, 日本語, 한국어, 简体中文, 繁體中文.
- `Accounts.swift`, `AuthCredentials.swift`, `LoginWindowController.swift` — multi-account storage and headless
  credential capture.
- `Engagement.swift` — shared engagement rules: blocked authors, rejection reporting, keeping every on-screen copy of
  a post in sync after a like / repost / bookmark.

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
  for what that costs and the helpers that absorb it).
- **Every on-screen copy of a post must stay in sync** after an engagement action: go through `Engagement` rather
  than mutating one view model.
- Build after touching a shared type — `swift build -c release` — before claiming anything works. There is no test
  target, so verification is a compile plus a run.

## Commits

Conventional commits, lowercase, imperative, scoped by area: `feat(detail):`, `fix(theme):`, `refactor(glass):`,
`chore(repo):`. The subject says what changed; the body says why it was needed and what the user now sees, wrapped at
120 columns. One logical change per commit, and keep it compiling.

## Known state

- `DebugSupport.swift` holds temporary scaffolding for the reply-threading work: set `MAX_DEBUG_DETAIL=1` in the
  environment to have the app open a busy post on launch and log how X's replies were grouped. It is inert otherwise.
  Delete the file and its two call sites once that work settles.
- The Messages tab is a placeholder (`NewDestinationPlaceholderView`); X's DMs are not implemented.
- There is no Bookmarks destination yet; bookmarking exists only as an action on posts.
