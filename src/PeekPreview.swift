//
//  PeekPreview.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Deep-press (Force Click) peek previews for media, links and profiles.
//
//  A Force Touch trackpad reports NSEvent.pressure events: stage 1 is a normal click, stage 2 the deep press.
//  Views opt in with `.peekable(...)`, which only records their frame in a registry (no AppKit view per row,
//  which would cost scrolling performance). On stage 2 the coordinator looks up the item under the pointer and
//  shows a card; releasing the press closes it. Three-finger-tap Look Up (`quickLook(with:)`) opens the same
//  card, which then stays until a click outside, Esc or a scroll.
//

import SwiftUI
import AppKit
import AVFoundation
import WebKit

// MARK: - Targets & Scope

enum PeekTarget: Equatable {
    case image(TweetMedia)
    case video(TweetMedia)
    case profile(TweetUser)
    case link(URL)
}

// Which surface a peekable belongs to, so presses only match items on the surface currently in front
enum PeekScope: Equatable {
    case none
    case timeline
    // A full-pane page; the index is its depth in the navigation stack
    case overlay(Int)
}

private struct PeekScopeKey: EnvironmentKey {
    static let defaultValue: PeekScope = .none
}

extension EnvironmentValues {
    var peekScope: PeekScope {
        get { self[PeekScopeKey.self] }
        set { self[PeekScopeKey.self] = newValue }
    }
}

// MARK: - Registry

final class PeekRegistry {
    static let shared = PeekRegistry()

    struct Entry {
        var frame: CGRect
        var scope: PeekScope
        // Point is local to the frame; lets text pick the link under the pointer
        var resolve: (CGPoint, CGSize) -> PeekTarget?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func update(_ key: ObjectIdentifier, entry: Entry) {
        entries[key] = entry
    }

    func remove(_ key: ObjectIdentifier) {
        entries.removeValue(forKey: key)
    }

    // Most specific (smallest) matching item wins, e.g. an avatar over its surrounding row
    func target(at point: CGPoint, scope: PeekScope) -> PeekTarget? {
        let hits = entries.values
            .filter { $0.scope == scope && $0.frame.contains(point) }
            .sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        for entry in hits {
            let local = CGPoint(x: point.x - entry.frame.minX, y: point.y - entry.frame.minY)
            if let target = entry.resolve(local, entry.frame.size) {
                return target
            }
        }
        return nil
    }
}

private final class PeekRegistration: ObservableObject {}

private struct PeekableModifier: ViewModifier {
    let resolve: (CGPoint, CGSize) -> PeekTarget?
    @Environment(\.peekScope) private var scope
    @StateObject private var registration = PeekRegistration()

    func body(content: Content) -> some View {
        if scope == .none {
            content
        } else {
            let key = ObjectIdentifier(registration)
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { [scope, resolve] frame in
                    PeekRegistry.shared.update(key, entry: .init(frame: frame, scope: scope, resolve: resolve))
                }
                .onDisappear {
                    PeekRegistry.shared.remove(key)
                }
        }
    }
}

extension View {
    func peekable(_ target: PeekTarget) -> some View {
        modifier(PeekableModifier { _, _ in target })
    }

    func peekable(resolve: @escaping (CGPoint, CGSize) -> PeekTarget?) -> some View {
        modifier(PeekableModifier(resolve: resolve))
    }
}

// MARK: - Link Hit Testing

enum PeekTextLinks {
    // Finds the link or @mention under a point in tweet body text by laying the text out with TextKit using the same
    // font, line spacing and width as the SwiftUI Text. A body with a single link and no mentions previews that link
    // from anywhere on the text.
    static func target(at point: CGPoint, size: CGSize, text: String, links: [DisplayLink]) -> PeekTarget? {
        let mentions = TweetText.mentionRanges(in: text, excluding: links)
        guard !links.isEmpty || !mentions.isEmpty else { return nil }
        if links.count == 1 && mentions.isEmpty { return URL(string: links[0].url).map(PeekTarget.link) }

        let theme = ThemeManager.shared
        let font: NSFont = theme.fontType == .mincho
            ? (NSFont(name: theme.activeSerifFontName, size: 15) ?? .systemFont(ofSize: 14.5))
            : .systemFont(ofSize: 14.5)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.lineSpacing()

        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: size.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard glyphRect.insetBy(dx: -6, dy: -4).contains(point) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)

        if let hit = links.first(where: { index >= $0.location && index < $0.location + $0.length }) {
            return URL(string: hit.url).map(PeekTarget.link)
        }
        if let mention = mentions.first(where: { NSLocationInRange(index, $0.range) }) {
            return .profile(TweetUser(id: "", name: mention.name, screenName: mention.name, avatarUrl: nil, isVerified: false))
        }
        return nil
    }
}

// MARK: - Coordinator

final class PeekCoordinator: ObservableObject {
    static let shared = PeekCoordinator()

    @Published private(set) var target: PeekTarget?
    // Stage-2 pressure (0...1) while the press is held; the card swells slightly with it
    @Published private(set) var pressure: CGFloat = 0
    // Opened by three-finger tap (or a press we couldn't track): stays open until dismissed
    @Published private(set) var isSticky = false

    var cardFrame: CGRect = .zero

    // Root hosting view: frames are recorded in SwiftUI's .global space, which is this view's (flipped) space
    private weak var hostingView: NSView?
    private var monitor: Any?
    private var lastStage = 0
    // The peek belongs to the press in progress and closes when that press is released
    private var closesOnRelease = false
    private var pressPeekEndedAt: CFTimeInterval = 0

    // The release that ends a deep press still reaches SwiftUI as a click on the item underneath. Opening the
    // lightbox, video player, tweet detail or a link checks this, so a peek never also triggers them.
    var suppressesActivation: Bool {
        target != nil || CACurrentMediaTime() - pressPeekEndedAt < 0.5
    }

    func start(hostingView: NSView) {
        self.hostingView = hostingView
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.pressure, .leftMouseDown, .leftMouseUp, .keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    // Called by the root hosting view for system Look Up (three-finger tap, or Force Click when Look Up uses it)
    func quickLook(with event: NSEvent) -> Bool {
        guard target == nil, let found = targetAt(event) else { return target != nil }
        let mouseIsDown = NSEvent.pressedMouseButtons & 1 != 0
        present(found, sticky: !mouseIsDown)
        if mouseIsDown { closesOnRelease = true }
        return true
    }

    func dismiss() {
        guard target != nil else { return }
        target = nil
        pressure = 0
        isSticky = false
    }

    private func present(_ newTarget: PeekTarget, sticky: Bool) {
        isSticky = sticky
        pressure = 0
        target = newTarget
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .pressure:
            let stage = event.stage
            if stage >= 2 && lastStage < 2 && target == nil, let found = targetAt(event) {
                present(found, sticky: false)
                closesOnRelease = true
            }
            if target != nil && !isSticky && stage >= 2 {
                pressure = CGFloat(max(0, min(1, event.pressure)))
            }
            lastStage = stage
            return event

        case .leftMouseUp:
            lastStage = 0
            if closesOnRelease {
                closesOnRelease = false
                pressPeekEndedAt = CACurrentMediaTime()
                if !isSticky { dismiss() }
            }
            return event

        case .leftMouseDown:
            if target != nil && isSticky && !cardContains(event) {
                dismiss()
                return nil
            }
            return event

        case .keyDown:
            if target != nil && event.keyCode == 53 { // Esc
                dismiss()
                return nil
            }
            return event

        case .scrollWheel:
            if target != nil && isSticky && !cardContains(event) {
                dismiss()
            }
            return event

        default:
            return event
        }
    }

    private func swiftUIPoint(for event: NSEvent) -> CGPoint? {
        guard let host = hostingView, event.window === host.window else { return nil }
        let p = host.convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: host.isFlipped ? p.y : host.bounds.height - p.y)
    }

    private func cardContains(_ event: NSEvent) -> Bool {
        guard let point = swiftUIPoint(for: event) else { return false }
        return cardFrame.contains(point)
    }

    private func targetAt(_ event: NSEvent) -> PeekTarget? {
        guard let window = event.window, window === NSApp.mainWindow, window.attachedSheet == nil,
              let point = swiftUIPoint(for: event) else { return nil }
        let scope = activeScope()
        guard scope != .none else { return nil }
        return PeekRegistry.shared.target(at: point, scope: scope)
    }

    private func activeScope() -> PeekScope {
        let nav = NavigationManager.shared
        if LightboxManager.shared.isPresented || VideoLightboxManager.shared.isPresented
            || nav.isShowingCompose || nav.replyTargetTweet != nil {
            return .none
        }
        if nav.hasOverlay { return .overlay(nav.overlayStack.count - 1) }
        return nav.currentTab == .home ? .timeline : .none
    }
}

// MARK: - Overlay

struct PeekOverlay: View {
    @ObservedObject private var peek = PeekCoordinator.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let target = peek.target {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    PeekCard(target: target, container: geo.size)
                        .scaleEffect(1.0 + 0.03 * peek.pressure)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            PeekCoordinator.shared.cardFrame = frame
                        }
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: peek.target)
        .animation(.easeOut(duration: 0.08), value: peek.pressure)
        // Only a sticky (three-finger tap) peek takes clicks, so its web page can be scrolled and used
        .allowsHitTesting(peek.target != nil && peek.isSticky)
    }
}

// MARK: - Card

private struct PeekCard: View {
    let target: PeekTarget
    let container: CGSize

    var body: some View {
        content
            .background(ThemeManager.background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(ThemeManager.border, lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 12)
    }

    @ViewBuilder private var content: some View {
        switch target {
        case .image(let media):
            let size = mediaSize(media)
            ZStack {
                CachedAsyncImage(urlString: MediaCacheManager.shared.formatThumbUrl(media.mediaUrl), contentMode: .fit, targetSize: size)
                CachedAsyncImage(urlString: MediaHelpers.originalImageUrl(media.mediaUrl), placeholderColor: .clear, contentMode: .fit, targetSize: size)
            }
            .frame(width: size.width, height: size.height)
        case .video(let media):
            let size = mediaSize(media)
            PeekVideoView(media: media)
                .frame(width: size.width, height: size.height)
        case .profile(let user):
            PeekProfileCard(user: user)
                .frame(width: min(380, container.width * 0.9))
        case .link(let url):
            PeekLinkCard(url: url)
                .frame(width: min(container.width * 0.86, 920), height: container.height * 0.76)
        }
    }

    private func mediaSize(_ media: TweetMedia) -> CGSize {
        let maxW = container.width * 0.84
        let maxH = container.height * 0.78
        let ratio = max(0.2, media.aspectRatio)
        let w = min(maxW, maxH * ratio)
        return CGSize(width: w, height: w / ratio)
    }
}

// MARK: - Video

private struct PeekVideoView: NSViewRepresentable {
    let media: TweetMedia

    func makeNSView(context: Context) -> PeekPlayerView {
        let view = PeekPlayerView()
        if let url = Self.playbackURL(for: media) {
            view.play(url)
        }
        return view
    }

    func updateNSView(_ nsView: PeekPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: PeekPlayerView, coordinator: ()) {
        nsView.stop()
    }

    // A prefetched file when available, otherwise a mid-bitrate stream so the peek starts quickly
    private static func playbackURL(for media: TweetMedia) -> URL? {
        guard let info = media.videoInfo else { return nil }
        if let best = info.highestBitrateVariant?.url, let cached = MediaCacheManager.shared.cachedVideoURL(for: best) {
            return cached
        }
        let variants = info.sortedMp4Variants
        let pick = variants.first(where: { ($0.bitrate ?? 0) <= 2_200_000 }) ?? variants.last
        return pick.flatMap { URL(string: $0.url) }
    }
}

final class PeekPlayerView: NSView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var loopObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        player.isMuted = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func play(_ url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}

// MARK: - Profile

// A profile peek for something that is only a handle (an @mention) asks X for the rest first
private final class PeekProfileLoader: ObservableObject {
    @Published var user: TweetUser
    init(user: TweetUser) {
        self.user = user
        loadIfNeeded()
    }

    func loadIfNeeded() {
        guard user.id.isEmpty else { return }
        let handle = user.screenName
        if let profile = ProfilePreloader.shared.cached(handle)?.profile {
            user = profile.user
            return
        }
        APIClient.shared.fetchUserProfile(screenName: handle) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let profile) = result { self?.user = profile.user }
            }
        }
    }
}

private struct PeekProfileCard: View {
    @StateObject private var loader: PeekProfileLoader
    @ObservedObject private var loc = LocalizationManager.shared

    init(user: TweetUser) {
        _loader = StateObject(wrappedValue: PeekProfileLoader(user: user))
    }

    private var user: TweetUser { loader.user }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let banner = user.bannerUrl {
                        CachedAsyncImage(urlString: banner + "/600x200", placeholderColor: ThemeManager.accent.opacity(0.25), targetSize: CGSize(width: 380, height: 120))
                    } else {
                        ThemeManager.accent.opacity(0.25)
                    }
                }
                .frame(height: 120)
                .clipped()

                CachedAsyncImage(
                    urlString: user.avatarUrl?.replacingOccurrences(of: "_bigger", with: "_400x400"),
                    targetSize: CGSize(width: 72, height: 72)
                )
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().stroke(ThemeManager.background, lineWidth: 3))
                .offset(x: 16, y: 36)
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(user.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(ThemeManager.accent)
                    }
                }
                Text(user.formattedHandle)
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.secondaryText)

                if let bio = user.bio, !bio.isEmpty {
                    LinkedText.make(bio, links: user.bioLinks ?? [])
                        .font(.system(size: 13.5))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let location = user.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                }

                if user.followingCount != nil || user.followersCount != nil {
                    HStack(spacing: 16) {
                        countLabel(user.followingCount, loc.t("peek_following"))
                        countLabel(user.followersCount, loc.t("peek_followers"))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 44)
            .padding(.bottom, 16)
        }
    }

    private func countLabel(_ count: Int?, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(Self.format(count ?? 0))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(ThemeManager.secondaryText)
        }
    }

    private static func format(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1_000.0) }
        return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

// MARK: - Link

private final class PeekLinkState: ObservableObject {
    @Published var title: String = ""
    @Published var isLoading = true
}

private struct PeekLinkCard: View {
    let url: URL
    @StateObject private var state = PeekLinkState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title.isEmpty ? (url.host ?? url.absoluteString) : state.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if state.isLoading {
                    GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 14)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            PeekWebView(url: url, state: state)
        }
    }
}

private struct PeekWebView: NSViewRepresentable {
    let url: URL
    let state: PeekLinkState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        // Ephemeral store: a peek never reads or writes the user's cookies or site data
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: PeekLinkState
        init(state: PeekLinkState) { self.state = state }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.title = webView.title ?? ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }
    }
}
