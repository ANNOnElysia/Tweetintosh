//
//  PeekPreview.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Deep-press (Force Click) peek previews for media, links and profiles.
//
//  A Force Touch trackpad reports NSEvent.pressure events: stage 1 is a normal click, stage 2 the deep press.
//  Views opt in with `.peekable(...)`, which places an empty marker view behind them. On stage 2 the coordinator
//  looks up the marker under the pointer and shows a card; releasing the press closes it. Three-finger-tap Look Up
//  (`quickLook(with:)`) opens the same card, which then stays until a click outside, Esc or a scroll.
//

import SwiftUI
import AppKit
import AVFoundation
import CoreServices
import WebKit

// MARK: - Targets & Scope

enum PeekTarget: Equatable {
    case image(TweetMedia)
    case video(TweetMedia)
    case profile(TweetUser)
    case link(URL)
    // Not a card: a press on an ordinary word opens the system dictionary
    case word(PeekWord)
}

struct PeekWord: Equatable {
    let text: NSAttributedString
    // Where the word's baseline starts: local to the item when resolved, in window coordinates once found
    var baseline: CGPoint
}

// Which surface a peekable belongs to, so presses only match items on the surface currently in front
enum PeekScope: Equatable {
    case none
    case timeline
    case notifications
    case messages
    // The Videos tab's pages
    case videos
    // The contact list slid over the chat, which it takes the presses from
    case contactListOverlay
    // A page in the detail pane with another on top of it
    case paneHidden
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

    fileprivate let anchors = NSHashTable<PeekAnchorView>.weakObjects()
    fileprivate let cells = NSHashTable<TableCellGeometry>.weakObjects()

    // One item under the pointer, whichever way it was registered
    private struct Hit {
        let area: CGFloat
        let target: () -> PeekTarget?
        let toWindow: (CGPoint) -> CGPoint
    }

    // Most specific (smallest) matching item wins, e.g. an avatar over its surrounding row. Positions come from
    // AppKit at the moment of the press: inside a List the frames SwiftUI reports stop being updated as soon as the
    // table scrolls, so they would point at wherever a row was when it was laid out.
    func target(atWindowPoint point: CGPoint, scope: PeekScope) -> PeekTarget? {
        var hits: [Hit] = anchors.allObjects
            .filter { $0.scope == scope && $0.visiblyContains(windowPoint: point) }
            .map { anchor in
                Hit(area: anchor.bounds.width * anchor.bounds.height,
                    target: { anchor.resolve?(anchor.topLeftPoint(fromWindowPoint: point), anchor.bounds.size) },
                    toWindow: { anchor.windowPoint(fromTopLeftPoint: $0) })
            }
        for cell in cells.allObjects {
            guard let host = cell.hostView, host.window != nil else { continue }
            let local = host.convert(point, from: nil)
            guard host.bounds.intersection(host.visibleRect).contains(local) else { continue }
            for region in cell.peekRegions.values where region.scope == scope && region.frame.contains(local) {
                let origin = region.frame.origin
                hits.append(Hit(
                    area: region.frame.width * region.frame.height,
                    target: { region.resolve(CGPoint(x: local.x - origin.x, y: local.y - origin.y), region.frame.size) },
                    toWindow: { host.convert(CGPoint(x: $0.x + origin.x, y: $0.y + origin.y), to: nil) }
                ))
            }
        }
        for hit in hits.sorted(by: { $0.area < $1.area }) {
            guard let target = hit.target() else { continue }
            if case .word(var word) = target {
                word.baseline = hit.toWindow(word.baseline)
                return .word(word)
            }
            return target
        }
        return nil
    }

    func register(_ cell: TableCellGeometry) {
        cells.add(cell)
    }
}

// MARK: - Table Cells

// What a table cell's contents know about the cell they are in. An NSView per peekable or tappable item costs more to
// create and lay out than the text beside it, and inside a cell it isn't needed: scrolling moves the cell, so a position
// relative to the cell stays true however far the table has scrolled, and the cell's hosting view converts it when asked.
final class TableCellGeometry {
    static let spaceName = "TableCell"
    // For laying a row out to measure it, where nothing will ever ask where anything is
    static let forMeasuring = TableCellGeometry()

    struct PeekRegion {
        var frame: CGRect = .zero
        var scope: PeekScope = .none
        var resolve: (CGPoint, CGSize) -> PeekTarget? = { _, _ in nil }
    }

    weak var hostView: NSView?
    fileprivate(set) var peekRegions: [ObjectIdentifier: PeekRegion] = [:]
}

private struct TableCellGeometryKey: EnvironmentKey {
    static let defaultValue: TableCellGeometry? = nil
}

extension EnvironmentValues {
    var tableCellGeometry: TableCellGeometry? {
        get { self[TableCellGeometryKey.self] }
        set { self[TableCellGeometryKey.self] = newValue }
    }
}

// Lives exactly as long as the item in the cell's view tree, and takes its region with it. Not tied to onDisappear, which
// also fires when the whole cell goes off to the reuse pool and would leave it with no regions when it comes back.
private final class PeekRegionToken: ObservableObject {
    weak var cell: TableCellGeometry?

    deinit {
        cell?.peekRegions[ObjectIdentifier(self)] = nil
    }
}

private struct CellPeekRegion: ViewModifier {
    let cell: TableCellGeometry
    let scope: PeekScope
    let resolve: (CGPoint, CGSize) -> PeekTarget?
    @StateObject private var token = PeekRegionToken()

    func body(content: Content) -> some View {
        // Not state that drives anything on screen, so it is safe to bring up to date here: it is only read during a press
        let key = ObjectIdentifier(token)
        token.cell = cell
        var region = cell.peekRegions[key] ?? TableCellGeometry.PeekRegion()
        region.scope = scope
        region.resolve = resolve
        cell.peekRegions[key] = region
        return content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TableCellGeometry.spaceName))
        } action: { [cell] frame in
            cell.peekRegions[key]?.frame = frame
        }
    }
}

// Marks where a peekable item is. It draws nothing and takes no clicks, and only gets read when a press happens, so
// scrolling does no work for it.
fileprivate final class PeekAnchorView: NSView {
    var scope: PeekScope = .none
    // Point is local to the item, from its top left; lets text pick the link under the pointer
    var resolve: ((CGPoint, CGSize) -> PeekTarget?)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // The visible part only, so a row scrolled underneath the header doesn't answer for a press on the header
    func visiblyContains(windowPoint: CGPoint) -> Bool {
        guard window != nil else { return false }
        // visibleRect alone can be wider than the view: views no longer clip to their bounds by default, so it
        // spans the whole row
        return bounds.intersection(visibleRect).contains(convert(windowPoint, from: nil))
    }

    func windowPoint(fromTopLeftPoint point: CGPoint) -> CGPoint {
        convert(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y), to: nil)
    }

    func topLeftPoint(fromWindowPoint windowPoint: CGPoint) -> CGPoint {
        let local = convert(windowPoint, from: nil)
        return CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
    }
}

private struct PeekAnchor: NSViewRepresentable {
    let scope: PeekScope
    let resolve: (CGPoint, CGSize) -> PeekTarget?

    func makeNSView(context: Context) -> PeekAnchorView {
        let view = PeekAnchorView()
        PeekRegistry.shared.anchors.add(view)
        return view
    }

    func updateNSView(_ view: PeekAnchorView, context: Context) {
        view.scope = scope
        view.resolve = resolve
    }

    static func dismantleNSView(_ view: PeekAnchorView, coordinator: ()) {
        PeekRegistry.shared.anchors.remove(view)
    }
}

private struct PeekableModifier: ViewModifier {
    let resolve: (CGPoint, CGSize) -> PeekTarget?
    @Environment(\.peekScope) private var scope
    @Environment(\.tableCellGeometry) private var cell

    func body(content: Content) -> some View {
        if scope == .none {
            content
        } else if let cell = cell {
            content.modifier(CellPeekRegion(cell: cell, scope: scope, resolve: resolve))
        } else {
            content.background(PeekAnchor(scope: scope, resolve: resolve))
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

    // For a post's body text: a deep press previews a link or @mention, and looks up any other word
    func peeksText(of tweet: Tweet, fontSize: CGFloat, lineSpacing: CGFloat) -> some View {
        peekable { [tweet] point, size in
            PeekTextLinks.target(at: point, size: size, text: tweet.displayBodyText, links: tweet.displayLinks,
                                 fontSize: fontSize, lineSpacing: lineSpacing)
        }
    }
}

// MARK: - Link Hit Testing

enum PeekTextLinks {
    // Finds what is under a point in tweet body text by laying the text out with TextKit using the same font, line
    // spacing and width as the SwiftUI Text: a link, an @mention, or else the word to look up.
    static func target(at point: CGPoint, size: CGSize, text: String, links: [DisplayLink],
                       fontSize: CGFloat, lineSpacing: CGFloat) -> PeekTarget? {
        let theme = ThemeManager.shared
        let font: NSFont = theme.fontType == .mincho
            ? (NSFont(name: theme.activeSerifFontName, size: fontSize + 0.5) ?? .systemFont(ofSize: fontSize))
            : .systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing

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
        let mentions = TweetText.mentionRanges(in: text, excluding: links)
        if let mention = mentions.first(where: { NSLocationInRange(index, $0.range) }) {
            return .profile(TweetUser(id: "", name: mention.name, screenName: mention.name, avatarUrl: nil, isVerified: false))
        }

        let range = wordRange(in: storage, at: index)
        let word = (text as NSString).substring(with: range)
        guard word.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        let start = layout.glyphIndexForCharacter(at: range.location)
        let line = layout.lineFragmentRect(forGlyphAt: start, effectiveRange: nil)
        let location = layout.location(forGlyphAt: start)
        return .word(PeekWord(text: NSAttributedString(string: word, attributes: [.font: font]),
                              baseline: CGPoint(x: line.minX + location.x, y: line.minY + location.y)))
    }

    // The dictionary's own idea of the term first, which is what splits Chinese and Japanese into words. Text it has
    // no term for still gets the word a double-click would select.
    private static func wordRange(in storage: NSTextStorage, at index: Int) -> NSRange {
        let term = DCSGetTermRangeInString(nil, storage.string as CFString, index)
        if term.location != kCFNotFound, term.length > 0 {
            return NSRange(location: term.location, length: term.length)
        }
        return storage.doubleClick(at: index)
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
    private var wordShownAt: CFTimeInterval = 0

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
            // Not `self?.handle(event) ?? event`: that turns a swallowed event (nil) back into the event, so Esc
            // would still reach the window and beep.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    // Called by the root hosting view for system Look Up (three-finger tap, or Force Click when Look Up uses it)
    func quickLook(with event: NSEvent) -> Bool {
        // With Look Up set to Force Click, one press arrives here as well as through the pressure events
        guard CACurrentMediaTime() - wordShownAt > 1 else { return true }
        guard target == nil, let found = targetAt(event) else { return target != nil }
        let mouseIsDown = NSEvent.pressedMouseButtons & 1 != 0
        if case .word(let word) = found {
            showDefinition(word)
            if mouseIsDown { closesOnRelease = true }
            return true
        }
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

    private func showDefinition(_ word: PeekWord) {
        guard let host = hostingView else { return }
        wordShownAt = CACurrentMediaTime()
        host.showDefinition(for: word.text, at: host.convert(word.baseline, from: nil))
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
                if case .word(let word) = found {
                    showDefinition(word)
                } else {
                    present(found, sticky: false)
                }
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
            // A deep press starts as a click, which gives the profile preview a head start
            if target == nil, case .profile(let user)? = targetAt(event) {
                ProfilePreloader.shared.preloadCard(user)
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
              let host = hostingView, window === host.window else { return nil }
        let scope = activeScope()
        guard scope != .none else { return nil }
        return PeekRegistry.shared.target(atWindowPoint: event.locationInWindow, scope: scope)
    }

    private func activeScope() -> PeekScope {
        let nav = NavigationManager.shared
        if LightboxManager.shared.isPresented || VideoLightboxManager.shared.isPresented
            || nav.isShowingCompose || nav.replyTargetTweet != nil || DMMessageMenuManager.shared.active != nil
            || TweetOptionsMenuManager.shared.activeMenu != nil {
            return .none
        }
        if nav.hasOverlay { return .overlay(nav.overlayStack.count - 1) }
        switch nav.currentTab {
        case .home: return .timeline
        case .notifications: return .notifications
        case .messages: return nav.isContactListPeeking ? .contactListOverlay : .messages
        case .videos: return .videos
        }
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
        case .word:
            EmptyView()
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
        if let url = MediaHelpers.previewPlaybackURL(for: media) {
            view.play(url)
        }
        return view
    }

    func updateNSView(_ nsView: PeekPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: PeekPlayerView, coordinator: ()) {
        nsView.stop()
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
        // Only a handle (an @mention), or a person from a notification, who comes without a bio or banner
        guard user.id.isEmpty || (user.bio == nil && user.bannerUrl == nil) else { return }
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
    @ObservedObject private var theme = ThemeManager.shared

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
                        .font(theme.appFont(size: 17, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(ThemeManager.accent)
                    }
                }
                Text(user.formattedHandle)
                    .font(theme.appFont(size: 13.5))
                    .foregroundColor(ThemeManager.secondaryText)

                if let bio = user.bio, !bio.isEmpty {
                    LinkedText.make(bio, links: user.bioLinks ?? [])
                        .font(theme.appFont(size: 13.5))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let location = user.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(theme.appFont(size: 12.5))
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
                .font(theme.appFont(size: 13, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            Text(title)
                .font(theme.appFont(size: 13))
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
                    LoadingIndicator(compactHeight: 18)
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
