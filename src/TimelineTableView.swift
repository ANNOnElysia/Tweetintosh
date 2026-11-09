//
//  TimelineTableView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The Home timeline as an NSTableView with NSHostingView cells, in place of a SwiftUI List. A List gives each post that
//  scrolls in a new identity and rebuilds its whole view tree, which costs more than a frame at 120 Hz however simple the
//  row is. Here a cell keeps its view tree and is handed the next post, which costs about half as much.
//
//  What that asks of everything else:
//  - State inside a row outlives the post it was made for, so row views key their state by post (see HoverReader,
//    ImageLoader, AutoplayVideoView)
//  - The SwiftUI environment and named coordinate spaces stop at each cell's hosting view
//  - The table needs every row's height up front, so TimelineRowHeights answers at once from an estimate and measures
//    visible and nearby rows between frames
//
//  This is a spike: `defaults write com.anno.tweetintosh Tweetintosh_TimelineUsesTable -bool false` goes back to the List.
//

import SwiftUI
import AppKit
import Combine

enum TimelineBackend {
    static let usesTable = UserDefaults.standard.object(forKey: "Tweetintosh_TimelineUsesTable") as? Bool ?? true
}

// MARK: - Row Content

// True while a row is laid out only to learn its height. Pictures there are never seen, so their loading is skipped.
private struct IsMeasuringRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMeasuringRow: Bool {
        get { self[IsMeasuringRowKey.self] }
        set { self[IsMeasuringRowKey.self] = newValue }
    }
}

// What a cell hosts. The environment is set here because it doesn't cross into a cell's hosting view.
struct TimelineRowContent: View {
    let tweet: Tweet
    let mediaColumnWidth: CGFloat?
    var isMeasuring = false
    var cellGeometry: TableCellGeometry?

    var body: some View {
        if isMeasuring {
            // No peek anchors, players or scroll subscriptions: none of them changes the height, and they are most of what
            // a row costs to build
            TweetRowView(tweet: tweet)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .environment(\.peekScope, .none)
                .environment(\.allowsVideoAutoplay, false)
                .environment(\.mediaColumnWidth, mediaColumnWidth)
                .environment(\.tableCellGeometry, TableCellGeometry.forMeasuring)
                .environment(\.isMeasuringRow, true)
        } else {
            TweetRowView(tweet: tweet)
                .modifier(PausesHitTestingWhileScrolling())
                // Pinned to the top, so a row still on its estimated height never shifts inside its cell
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coordinateSpace(name: TableCellGeometry.spaceName)
                .environment(\.peekScope, .timeline)
                .environment(\.allowsVideoAutoplay, true)
                .environment(\.mediaColumnWidth, mediaColumnWidth)
                .environment(\.tableCellGeometry, cellGeometry)
        }
    }
}

// MARK: - Row Heights

// Remembers each post's height for as long as nothing that affects it changes, so a tab switch or a return to a feed needs
// no measuring. A like or a new count never changes a row's height, so those keep their entry.
final class TimelineRowHeights {
    static let shared = TimelineRowHeights()

    // Everything outside a post that its height depends on
    struct Context: Equatable {
        var rowWidth: CGFloat
        var mediaColumnWidth: CGFloat?
        var fontType: AppFontType
        var language: AppLanguage
    }

    private struct Entry {
        var signature: Int
        var height: CGFloat
        var isExact: Bool
    }

    private var entries: [String: Entry] = [:]
    private(set) var context = Context(rowWidth: 0, mediaColumnWidth: nil, fontType: .system, language: .english)
    private lazy var sizer = NSHostingController(
        rootView: TimelineRowContent(tweet: Self.placeholderTweet, mediaColumnWidth: nil, isMeasuring: true)
    )

    private static let placeholderTweet = Tweet(
        id: "", text: "", createdAt: Date(timeIntervalSince1970: 0),
        author: TweetUser(id: "", name: "", screenName: "", avatarUrl: nil, isVerified: false),
        media: [], replyCount: 0, retweetCount: 0, favoriteCount: 0, isRetweet: false, retweetedBy: nil
    )

    func setContext(_ newValue: Context) {
        guard newValue != context else { return }
        context = newValue
        // Estimates for the new width are worked out as rows are asked for; the old measurements no longer apply
        entries.removeAll(keepingCapacity: true)
    }

    func height(for tweet: Tweet) -> CGFloat {
        let signature = Self.signature(of: tweet)
        if let entry = entries[tweet.id], entry.signature == signature { return entry.height }
        let estimate = TimelineRowEstimator.height(of: tweet, context: context)
        entries[tweet.id] = Entry(signature: signature, height: estimate, isExact: false)
        return estimate
    }

    func isMeasured(_ tweet: Tweet) -> Bool {
        guard let entry = entries[tweet.id] else { return false }
        return entry.isExact && entry.signature == Self.signature(of: tweet)
    }

    // Lays the row out for real, on the main thread, so the caller decides when there is room for it
    func measure(_ tweet: Tweet) -> CGFloat {
        sizer.rootView = TimelineRowContent(tweet: tweet, mediaColumnWidth: context.mediaColumnWidth, isMeasuring: true)
        let size = sizer.sizeThatFits(in: CGSize(width: context.rowWidth, height: .greatestFiniteMagnitude))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let height = max(1, ceil(size.height * scale) / scale)
        entries[tweet.id] = Entry(signature: Self.signature(of: tweet), height: height, isExact: true)
        return height
    }

    private static func signature(of tweet: Tweet) -> Int {
        var hasher = Hasher()
        hasher.combine(tweet.displayBodyText)
        hasher.combine(tweet.replyContextText)
        hasher.combine(tweet.isRetweet)
        hasher.combine(tweet.media.count)
        hasher.combine(tweet.media.first?.id)
        hasher.combine(tweet.quotedTweet?.tweet.id)
        hasher.combine(tweet.quotedTweet?.tweet.displayBodyText)
        hasher.combine(tweet.article?.title)
        // A card's height changes when its preview arrives, without the post itself changing
        hasher.combine(tweet.linksToArticle && ArticlePreviewStore.shared.previews[tweet.id] != nil)
        return hasher.finalize()
    }
}

// Works out roughly how tall a row will be from its text and media alone, cheaply enough to do for a whole page at once.
// It only has to be close: it decides the scroll bar and how far the content below sits until the row is measured.
enum TimelineRowEstimator {
    private static let textColumnInset: CGFloat = 82      // Margins, avatar and spacing beside a post's text

    static func height(of tweet: Tweet, context: TimelineRowHeights.Context) -> CGFloat {
        let textWidth = max(120, context.rowWidth - textColumnInset)
        let spacing = ThemeManager.shared.lineSpacing()
        var column: CGFloat = 24 // The header is as tall as the options button

        if tweet.replyContextText != nil { column += 6 + 16 }
        if !tweet.displayBodyText.isEmpty {
            column += 6 + textHeight(tweet.displayBodyText, fontSize: 14.5, width: textWidth, lineSpacing: spacing)
        }
        if !tweet.media.isEmpty {
            column += 6 + 2 + ImageGridView.contentHeight(mediaList: tweet.media, isQuoted: false, mediaColumnWidth: context.mediaColumnWidth)
        }
        if tweet.linksToArticle {
            column += 6 + 4 + 96
        }
        if let quoted = tweet.quoted {
            var card: CGFloat = 10 + 20 + 10
            if quoted.replyContextText != nil { card += 8 + 15 }
            if !quoted.displayBodyText.isEmpty {
                let body = textHeight(quoted.displayBodyText, fontSize: 13, width: textWidth - 20, lineSpacing: spacing * 0.8)
                card += 8 + min(body, 4 * (16 + spacing * 0.8))
            }
            if !quoted.media.isEmpty {
                card += 8 + ImageGridView.contentHeight(mediaList: quoted.media, isQuoted: true, mediaColumnWidth: context.mediaColumnWidth)
            }
            column += 6 + 4 + card
        }

        let top: CGFloat = (tweet.isRetweet && tweet.retweetedBy != nil) ? 10 + 16 + 6 : 12
        let actions: CGFloat = 8 + 18 + 12
        return ceil(top + column + actions + 1)
    }

    private static func textHeight(_ text: String, fontSize: CGFloat, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let theme = ThemeManager.shared
        let font: NSFont = theme.fontType == .mincho
            ? (NSFont(name: theme.activeSerifFontName, size: fontSize + 0.5) ?? .systemFont(ofSize: fontSize))
            : .systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        return ceil(rect.height)
    }
}

// MARK: - AppKit Views

final class TimelineNSTableView: NSTableView {
    // Otherwise the table takes the click for row selection, and it never reaches the SwiftUI buttons inside a cell
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
}

// Makes a trackpad swipe on Home travel further, in proportion to how fast it is. A finger on a touch screen is left 1:1,
// since the content has to stay under it. Slow movement stays 1:1 so the content still follows
// the finger while reading, and because momentum slows down gradually, the glide eases back to 1:1 with no visible step.
//
// Done on the clip view's steps rather than on the scroll events: with responsive scrolling AppKit passes only the first
// event of a gesture to scrollWheel and runs the rest itself, and turning responsive scrolling off to see them all adds about
// 5 ms of main-thread work to every frame of a scroll. Each step it takes still comes through scroll(to:), momentum included.
final class TimelineClipView: NSClipView {
    // Fast swipes used to be multiplied by up to 2.5, but AppKit's step sizes vary within one gesture, so the same
    // finger movement can cover different distances from frame to frame and read as a stutter. The default is now
    // 1:1; `Tweetintosh_TimelineScrollBoost` remains available as an opt-in for faster travel.
    private static let maximumGain = CGFloat(UserDefaults.standard.object(forKey: "Tweetintosh_TimelineScrollBoost") as? Double ?? 1)
    // Points per step: at or below the first the gain is 1, and at or above the second it is the maximum
    private static let slowStep: CGFloat = 2
    private static let fastStep: CGFloat = 24

    // Only a trackpad gesture and its momentum are boosted. Keyboard scrolling, scrolling to the top and keeping the reader's
    // place when rows change all move the clip view too, and must land exactly where they aim.
    private var isInLiveScroll = false
    private var observers: [NSObjectProtocol] = []

    func watchLiveScroll(of scrollView: NSScrollView) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                self?.isInLiveScroll = true
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                self?.isInLiveScroll = false
            }
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // A programmatic move in the middle of a gesture, such as keeping the reader's place when a row above changes height
    func scrollExactly(to point: NSPoint) {
        let wasLive = isInLiveScroll
        isInLiveScroll = false
        scroll(to: point)
        isInLiveScroll = wasLive
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: boosted(newOrigin))
    }

    private func boosted(_ proposed: NSPoint) -> NSPoint {
        guard isInLiveScroll, !ScrollInput.shared.isDirectTouch, Self.maximumGain > 1, let scrollView = enclosingScrollView, let document = documentView else { return proposed }
        let current = bounds.minY
        let step = proposed.y - current
        let topY = scrollView.restingTopY
        let bottomY = max(topY, document.frame.height - bounds.height)
        // The rubber band at either end stays 1:1, and with it the distance a pull takes to refresh
        guard current >= topY, current <= bottomY, proposed.y >= topY, proposed.y <= bottomY else { return proposed }

        let position = min(1, max(0, (abs(step) - Self.slowStep) / (Self.fastStep - Self.slowStep)))
        let gain = 1 + (Self.maximumGain - 1) * position * position * (3 - 2 * position)
        let y = min(bottomY, max(topY, current + step * gain))
        return NSPoint(x: proposed.x, y: y)
    }
}

final class TimelineNSScrollView: NSScrollView {
    var onWindowChange: (() -> Void)?
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowChange?() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width != lastWidth else { return }
        lastWidth = newSize.width
        // Later: changing row heights during the table's own layout is an operation it doesn't allow
        DispatchQueue.main.async { [weak self] in self?.onWidthChange?() }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        onWidthChange?()
    }
}

// Cells size their hosting view themselves, on every layout. Autoresizing drifted: after the sidebar's animation changed
// the column's width a frame at a time, hosting views were left wider or shorter than their cells, so a post's actions slid
// under the next row and a too-wide post shifted sideways under the sidebar. Cells also clip, so a post whose height is
// still being worked out never draws over its neighbour.
private class TimelineCellBase: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hostedView: NSView? { nil }

    // While a row glides to a new height (Show more / Show less), its post is laid out once at the final height and
    // pinned to the top, and the cell's clipping reveals or hides it. Resizing the post on every frame of the glide
    // made it jump inside its row.
    var pinnedHeight: CGFloat? {
        didSet { updateHostedFrame() }
    }

    private var hostedFrame: NSRect {
        guard let height = pinnedHeight else { return bounds }
        return NSRect(x: 0, y: isFlipped ? 0 : bounds.height - height, width: bounds.width, height: height)
    }

    private func updateHostedFrame() {
        // AppKit can ask for layout repeatedly while a table scrolls; writing an unchanged frame back makes the hosting
        // view run its layout again for no visible change.
        guard let hosted = hostedView, hosted.frame != hostedFrame else { return }
        hosted.frame = hostedFrame
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        updateHostedFrame()
    }

    override func layout() {
        super.layout()
        updateHostedFrame()
    }

    func install(_ hosted: NSView) {
        hosted.translatesAutoresizingMaskIntoConstraints = true
        hosted.autoresizingMask = []
        hosted.frame = hostedFrame
        addSubview(hosted)
    }
}

private final class TimelineTweetCell: TimelineCellBase {
    static let identifier = NSUserInterfaceItemIdentifier("TimelineTweetCell")
    private(set) var content: TimelineRowContent?
    private var host: FocusCachingHostingView<TimelineRowContent>?
    private let geometry: TableCellGeometry = {
        let geometry = TableCellGeometry()
        PeekRegistry.shared.register(geometry)
        return geometry
    }()

    override var hostedView: NSView? { host }

    func show(_ row: TimelineRowContent) {
        // Nothing to do when a page is only being asked to refresh: comparing here spares SwiftUI the whole row
        if let content = content, content.tweet == row.tweet, content.mediaColumnWidth == row.mediaColumnWidth { return }
        // A reused cell must not keep a pin meant for the post it showed before
        if content?.tweet.id != row.tweet.id { pinnedHeight = nil }
        var newContent = row
        newContent.cellGeometry = geometry
        content = newContent
        if let host = host {
            host.rootView = newContent
        } else {
            let host = FocusCachingHostingView(rootView: newContent)
            // No measuring of its own and no titlebar inset: the table sets the frame, and the titlebar is the spacer's job
            host.sizingOptions = []
            host.safeAreaRegions = []
            install(host)
            self.host = host
            geometry.hostView = host
        }
    }
}

private final class TimelineFooterCell: TimelineCellBase {
    static let identifier = NSUserInterfaceItemIdentifier("TimelineFooterCell")
    private var host: NSHostingView<LoadingIndicator>?
    private var active: Bool?

    override var hostedView: NSView? { host }

    func show(active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if let host = host {
            host.rootView = LoadingIndicator(active: active)
        } else {
            let host = NSHostingView(rootView: LoadingIndicator(active: active))
            host.sizingOptions = []
            host.safeAreaRegions = []
            install(host)
            self.host = host
        }
    }
}

// MARK: - SwiftUI Bridge

struct TimelineTableView: NSViewRepresentable {
    let tweets: [Tweet]
    let isLoadingMore: Bool
    let topSpacerHeight: CGFloat
    let onLoadMore: () -> Void

    @Environment(\.mediaColumnWidth) private var mediaColumnWidth

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TimelineNSScrollView {
        let coordinator = context.coordinator
        let scrollView = coordinator.scrollView
        coordinator.parent = self
        scrollView.onWindowChange = { [weak coordinator] in coordinator?.attachToScrollCoordinators() }
        scrollView.onWidthChange = { [weak coordinator] in coordinator?.widthDidChange() }
        coordinator.update(from: self)
        return scrollView
    }

    // Takes whatever it is offered. Without an answer here SwiftUI asks AppKit for the view's fitting size, and AppKit works
    // that out by loading the constraints of every view inside it into a temporary layout engine: every cell's hosting view
    // and every anchor in them, which was a third of the time in frames that hitched.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TimelineNSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ nsView: TimelineNSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(from: self)
        context.coordinator.attachToScrollCoordinators()
    }

    static func dismantleNSView(_ nsView: TimelineNSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        // Row 0 is the spacer under the floating bars and the last row the load-more indicator
        private static let footerHeight: CGFloat = 60
        // Room for one row's measurement in one tick, between frames
        private static let measureInterval: TimeInterval = 1.0 / 30.0
        // How far beyond the screen rows get measured while scrolling, so they are exact by the time they arrive
        private static let lookAheadRows = 4
        // A small bound on rows kept ready ahead of the viewport; the window follows scroll direction and speed.
        private static let prewarmLimit = 4

        let scrollView = TimelineNSScrollView()
        private let tableView = TimelineNSTableView()
        private let heights = TimelineRowHeights.shared
        var parent: TimelineTableView?

        private var tweets: [Tweet] = []
        private var ids: [String] = []
        // Parallel to tweets. The table reads these on every layout, so they stay plain values rather than cache lookups.
        private var rowHeights: [CGFloat] = []
        private var prewarmPool: [String: TimelineTweetCell] = [:]
        private var boundsObserver: NSObjectProtocol?
        private var lastScrollY: CGFloat?
        private var lastScrollTime: CFTimeInterval = 0
        private var scrollDirection: CGFloat = 1
        private var scrollVelocity: CGFloat = 0
        private var topSpacerHeight: CGFloat = 0
        private var isLoadingMore = false
        private var measureTimer: Timer?
        // Rows gliding to a new height after Show more / Show less
        private struct Glide { let id: String; let from: CGFloat; let to: CGFloat }
        private var glides: [Glide] = []
        private var glideStart: CFTimeInterval = 0
        private var glideTimer: Timer?
        private static let glideDuration: CFTimeInterval = 0.28
        private var lastCellShownAt: CFTimeInterval = 0
        private var articleObserver: AnyCancellable?

        override init() {
            super.init()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("post"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.style = .plain
            tableView.intercellSpacing = .zero
            tableView.backgroundColor = .clear
            tableView.gridStyleMask = []
            tableView.selectionHighlightStyle = .none
            tableView.allowsTypeSelect = false
            tableView.allowsColumnReordering = false
            tableView.focusRingType = .none
            tableView.refusesFirstResponder = true
            tableView.usesAutomaticRowHeights = false
            tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
            tableView.dataSource = self
            tableView.delegate = self

            let clipView = TimelineClipView()
            scrollView.contentView = clipView
            clipView.watchLiveScroll(of: scrollView)
            scrollView.documentView = tableView
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay

            // A preview arriving changes that post's card, with no change to the post for update(from:) to notice
            articleObserver = ArticlePreviewStore.shared.$previews
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshArticleRows() }
        }

        func tearDown() {
            measureTimer?.invalidate()
            measureTimer = nil
            prewarmPool.removeAll()
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
        }

        // The same three registrations the List's top row makes through ScrollViewAccessor
        func attachToScrollCoordinators() {
            guard scrollView.window != nil else { return }
            if boundsObserver == nil {
                scrollView.contentView.postsBoundsChangedNotifications = true
                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
                ) { [weak self] _ in self?.scrollDidMove() }
                lastScrollY = scrollView.contentView.bounds.minY
                lastScrollTime = CACurrentMediaTime()
            }
            TimelineScrollCoordinator.shared.registerScrollView(scrollView)
            TrackpadPullCoordinator.shared.attachScrollView(scrollView, owner: "Timeline")
            ListLoadMoreWatcher.shared.attach(scrollView) { [weak self] in self?.parent?.onLoadMore() }
        }

        // Speed is read from the content itself, so the eventual prewarm follows the accelerated distance rather than
        // just the trackpad's unaccelerated event distance.
        private func scrollDidMove() {
            let clip = scrollView.contentView.bounds
            let y = clip.minY
            let now = CACurrentMediaTime()
            guard let previousY = lastScrollY else {
                lastScrollY = y
                lastScrollTime = now
                return
            }
            let delta = y - previousY
            let elapsed = now - lastScrollTime
            lastScrollY = y
            lastScrollTime = now
            guard abs(delta) >= 0.5, elapsed > 0, elapsed < 0.12 else { return }
            // A jump, anchor restore or window resize is not a wheel gesture.
            guard abs(delta) < clip.height else {
                scrollVelocity = 0
                return
            }
            scrollDirection = delta > 0 ? 1 : -1
            scrollVelocity = delta / max(elapsed, 0.008)
        }

        // MARK: Data Updates

        func update(from view: TimelineTableView) {
            // The first layout needs heights at once; after that, a change of width waits until it stops changing
            if heights.context.rowWidth == 0 || tweets.isEmpty {
                applyHeightContext()
            } else {
                followWidth()
            }
            applyTopSpacer(view.topSpacerHeight)
            applyTweets(view.tweets)
            if view.isLoadingMore != isLoadingMore {
                isLoadingMore = view.isLoadingMore
                let footerRow = tweets.count + 1
                (tableView.view(atColumn: 0, row: footerRow, makeIfNecessary: false) as? TimelineFooterCell)?.show(active: isLoadingMore)
            }
        }

        private func applyTweets(_ newTweets: [Tweet]) {
            guard newTweets != tweets else { return }
            let newIds = newTweets.map(\.id)
            if newIds == ids {
                applyChangedPosts(newTweets)
                return
            }

            // A page of older posts arrives at the bottom, leaving every row above it untouched. Inserting just the new
            // rows keeps the existing heights and avoids diffing and laying out the whole feed again.
            let oldCount = tweets.count
            if oldCount > 0,
               newIds.count > oldCount,
               newIds.prefix(oldCount).elementsEqual(ids),
               newTweets.prefix(oldCount).elementsEqual(tweets) {
                appendTweets(newTweets, newIds: newIds, from: oldCount)
                return
            }

            prewarmPool.removeAll()
            let anchor = captureAnchor()
            let difference = newIds.difference(from: ids)
            let changeCount = difference.insertions.count + difference.removals.count
            let wasEmpty = tweets.isEmpty
            let replacesMost = changeCount > max(40, ids.count)

            tweets = newTweets
            ids = newIds
            rowHeights = newTweets.map { heights.height(for: $0) }

            if wasEmpty || replacesMost {
                // Another feed, with little or nothing in common: nothing to carry across
                tableView.reloadData()
            } else {
                tableView.beginUpdates()
                for change in difference {
                    switch change {
                    case .remove(let offset, _, _):
                        tableView.removeRows(at: IndexSet(integer: offset + 1), withAnimation: .effectFade)
                    case .insert(let offset, _, _):
                        tableView.insertRows(at: IndexSet(integer: offset + 1), withAnimation: [])
                    }
                }
                tableView.endUpdates()
            }
            restore(anchor)
            scheduleMeasuring()
        }

        private func appendTweets(_ newTweets: [Tweet], newIds: [String], from oldCount: Int) {
            tweets = newTweets
            ids = newIds
            rowHeights.append(contentsOf: newTweets[oldCount...].map { heights.height(for: $0) })
            tableView.beginUpdates()
            tableView.insertRows(at: IndexSet(integersIn: (oldCount + 1)..<(newIds.count + 1)), withAnimation: [])
            tableView.endUpdates()
            scheduleMeasuring()
        }

        // The same posts with new contents (a like, a repost): only what's on screen has anything to redraw
        private func applyChangedPosts(_ newTweets: [Tweet]) {
            let old = tweets
            tweets = newTweets
            var changedHeights = IndexSet()
            var unfolded = IndexSet()
            for index in newTweets.indices where newTweets[index] != old[index] {
                // Show more / Show less: measured now, so the row can glide straight to its real height
                if newTweets[index].isTextExpanded != old[index].isTextExpanded {
                    let target = heights.measure(newTweets[index])
                    glides.removeAll { $0.id == newTweets[index].id }
                    glides.append(Glide(id: newTweets[index].id, from: rowHeights[index], to: target))
                    unfolded.insert(index + 1)
                    if let cell = tableView.view(atColumn: 0, row: index + 1, makeIfNecessary: false) as? TimelineTweetCell {
                        cell.pinnedHeight = target
                        cell.show(content(for: newTweets[index]))
                    }
                    continue
                }
                let height = heights.height(for: newTweets[index])
                if height != rowHeights[index] {
                    rowHeights[index] = height
                    changedHeights.insert(index + 1)
                }
                if let cell = tableView.view(atColumn: 0, row: index + 1, makeIfNecessary: false) as? TimelineTweetCell {
                    cell.show(content(for: newTweets[index]))
                }
            }
            if !changedHeights.isEmpty { noteHeightsChanged(changedHeights) }
            if !unfolded.isEmpty { animateUnfolding(unfolded) }
            scheduleMeasuring()
        }

        // The row grows or shrinks in place, a frame at a time, with its post laid out once at the final height and its
        // cell clipping it. The table's own animated height change can't be used: it gives the cell its final height at
        // once, anchored to the bottom of the growing row, which hides the top of the post until it ends. Shrinking a
        // post whose top has scrolled away brings its top back into view, so the reader is not left further down.
        private func animateUnfolding(_ rows: IndexSet) {
            // Room for the floating bar over the top of the timeline
            let clearance: CGFloat = 72
            let clip = scrollView.contentView
            if let row = rows.first, row - 1 < tweets.count, !tweets[row - 1].isTextExpanded {
                let top = tableView.rect(ofRow: row).minY
                if top < clip.bounds.minY + clearance {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = Self.glideDuration
                        clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.minX, y: max(scrollView.restingTopY, top - clearance)))
                    }
                }
            }
            glideStart = CACurrentMediaTime()
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { glideStart -= Self.glideDuration }
            stepGlides()
            guard glideTimer == nil, !glides.isEmpty else { return }
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.stepGlides() }
            RunLoop.main.add(timer, forMode: .common)
            glideTimer = timer
        }

        private func stepGlides() {
            let t = min(1, (CACurrentMediaTime() - glideStart) / Self.glideDuration)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            var rows = IndexSet()
            for glide in glides {
                guard let index = ids.firstIndex(of: glide.id) else { continue }
                rowHeights[index] = (glide.from + (glide.to - glide.from) * eased).rounded()
                if t >= 1 { rowHeights[index] = glide.to }
                rows.insert(index + 1)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.noteHeightOfRows(withIndexesChanged: rows)
            }
            guard t >= 1 else { return }
            glideTimer?.invalidate()
            glideTimer = nil
            for row in rows {
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineTweetCell)?.pinnedHeight = nil
            }
            glides.removeAll()
        }

        private func refreshArticleRows() {
            var changed = IndexSet()
            for (index, tweet) in tweets.enumerated() where tweet.linksToArticle && tweet.article == nil {
                let height = heights.height(for: tweet)
                if height != rowHeights[index] {
                    rowHeights[index] = height
                    changed.insert(index + 1)
                }
            }
            if !changed.isEmpty { noteHeightsChanged(changed) }
            scheduleMeasuring()
        }

        private func applyTopSpacer(_ height: CGFloat) {
            guard height != topSpacerHeight else { return }
            let isFirst = topSpacerHeight == 0
            topSpacerHeight = height
            guard !isFirst else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
            }
        }

        // Everything a row's height depends on, read from the table's real width. The media column is derived from it too,
        // so no cell is ever given picture sizes meant for a different width.
        private func currentHeightContext() -> TimelineRowHeights.Context {
            let clipWidth = scrollView.contentView.bounds.width
            let width = clipWidth > 0 ? clipWidth : ((parent?.mediaColumnWidth).map { $0 + Self.textColumnInset } ?? 760)
            return TimelineRowHeights.Context(
                rowWidth: width,
                mediaColumnWidth: width - Self.textColumnInset,
                fontType: ThemeManager.shared.fontType,
                language: LocalizationManager.shared.currentLanguage
            )
        }

        // Margins, avatar and spacing beside a post's text and media
        private static let textColumnInset: CGFloat = 82
        private var widthSettleWork: DispatchWorkItem?

        // Opening or closing the sidebar changes visible estimates with the column. Once it stops, nearby rows are
        // measured a row at a time so the final width does not trigger a burst of layout.
        private var followedWidth: CGFloat = 0

        private func followWidth() {
            let context = currentHeightContext()
            guard context.rowWidth != followedWidth, context != heights.context, !tweets.isEmpty else { return }
            followedWidth = context.rowWidth
            let anchor = captureAnchor()
            var changed = IndexSet()
            for row in visibleTweetRows() {
                let tweet = tweets[row - 1]
                let height = TimelineRowEstimator.height(of: tweet, context: context)
                if height != rowHeights[row - 1] {
                    rowHeights[row - 1] = height
                    changed.insert(row)
                }
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineTweetCell)?.show(content(for: tweet))
            }
            if !changed.isEmpty {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    tableView.noteHeightOfRows(withIndexesChanged: changed)
                }
            }
            restore(anchor)
            scheduleWidthSettle()
        }

        private func scheduleWidthSettle() {
            guard currentHeightContext() != heights.context else { return }
            widthSettleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.applyHeightContext() }
            widthSettleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func applyHeightContext() {
            widthSettleWork?.cancel()
            widthSettleWork = nil
            let newContext = currentHeightContext()
            guard newContext != heights.context else { return }
            heights.setContext(newContext)
            prewarmPool.removeAll()
            if let column = tableView.tableColumns.first, column.width != newContext.rowWidth { column.width = newContext.rowWidth }
            guard !tweets.isEmpty else { return }
            let anchor = captureAnchor()
            // Keep the width change to estimates; exact layout is spread over later ticks, starting on screen.
            let visible = Set(visibleTweetRows())
            rowHeights = tweets.map { heights.height(for: $0) }
            for row in visible {
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineTweetCell)?.show(content(for: tweets[row - 1]))
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 1..<(tweets.count + 1)))
            }
            restore(anchor)
            scheduleMeasuring()
        }

        func widthDidChange() {
            followWidth()
        }

        // MARK: Scroll Anchoring

        // Keeps the post being read still when rows above it change, whether they were added, removed or re-measured
        private struct Anchor {
            let id: String
            let offset: CGFloat
        }

        private func captureAnchor() -> Anchor? {
            guard !tweets.isEmpty else { return nil }
            let clip = scrollView.contentView.bounds
            // At the top, new posts should come into view rather than push in above the screen
            guard clip.minY > scrollView.restingTopY + 0.5 else { return nil }
            let visible = tableView.rows(in: clip)
            let first = max(1, visible.location)
            guard first <= tweets.count else { return nil }
            return Anchor(id: ids[first - 1], offset: clip.minY - tableView.rect(ofRow: first).minY)
        }

        private func restore(_ anchor: Anchor?) {
            guard let anchor = anchor, let index = ids.firstIndex(of: anchor.id) else { return }
            let clip = scrollView.contentView
            // On whole device pixels, and corrected however small the difference: skipping the small ones let them add up
            // into a visible creep after the sidebar's animation, a pixel at a time
            let scale = scrollView.window?.backingScaleFactor ?? 2
            let y = ((tableView.rect(ofRow: index + 1).minY + anchor.offset) * scale).rounded() / scale
            guard y != clip.bounds.minY else { return }
            if let clip = clip as? TimelineClipView {
                clip.scrollExactly(to: NSPoint(x: clip.bounds.minX, y: y))
            } else {
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
            }
            scrollView.reflectScrolledClipView(clip)
        }

        private func noteHeightsChanged(_ rows: IndexSet) {
            let anchor = captureAnchor()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.noteHeightOfRows(withIndexesChanged: rows)
            }
            restore(anchor)
        }

        // MARK: Measuring

        // Keep the visible rows accurate without spending idle time measuring the entire feed.
        private func scheduleMeasuring() {
            guard measureTimer == nil, !tweets.isEmpty else { return }
            let timer = Timer(timeInterval: Self.measureInterval, repeats: true) { [weak self] _ in self?.measureTick() }
            // Common modes: the default mode doesn't run while a scroll is being tracked
            RunLoop.main.add(timer, forMode: .common)
            measureTimer = timer
        }

        private func measureTick() {
            // Width changes have their own deferred update, and a newly built cell already used this frame's time.
            guard currentHeightContext() == heights.context,
                  CACurrentMediaTime() - lastCellShownAt > 0.008 else { return }
            guard let index = nextRowToMeasure() else {
                if TimelineLiveScrollState.shared.isLiveScrolling { return }
                if prewarmNext() { return }
                measureTimer?.invalidate()
                measureTimer = nil
                return
            }
            let height = heights.measure(tweets[index])
            guard height != rowHeights[index] else { return }
            rowHeights[index] = height
            noteHeightsChanged(IndexSet(integer: index + 1))
        }

        // Build the rows the accelerated viewport is about to reach, one per tick. The window follows the content's
        // direction and speed, and is bounded so speculative work cannot grow with the feed.
        private func prewarmNext() -> Bool {
            guard !TimelineLiveScrollState.shared.isLiveScrolling, !tweets.isEmpty, !rowHeights.isEmpty else { return false }
            let clip = scrollView.contentView.bounds
            let visible = tableView.rows(in: clip)
            let firstVisible = max(1, visible.location)
            let lastVisible = min(tweets.count, visible.location + visible.length - 1)
            guard firstVisible <= lastVisible else {
                prewarmPool.removeAll()
                return false
            }

            let direction = scrollDirection >= 0 ? 1 : -1
            let anchor = direction > 0 ? lastVisible + 1 : firstVisible - 1
            let viewport = max(1, clip.height)
            let speed = TimelineLiveScrollState.shared.isLiveScrolling ? min(abs(scrollVelocity), 8000) : 0
            let targetDistance = min(viewport * 2, max(viewport * 0.5, viewport * 0.5 + speed * 0.2))

            var candidates: [Int] = []
            var distance: CGFloat = 0
            var row = anchor
            while row >= 1, row <= tweets.count, candidates.count < Self.prewarmLimit, distance < targetDistance {
                candidates.append(row)
                distance += max(1, rowHeights[row - 1])
                row += direction
            }
            guard !candidates.isEmpty else {
                prewarmPool.removeAll()
                return false
            }

            // Keep only rows still inside the current direction and window; a turn must not retain the old queue.
            let ahead = Set(candidates.map { tweets[$0 - 1].id })
            prewarmPool = prewarmPool.filter { ahead.contains($0.key) }
            guard prewarmPool.count < Self.prewarmLimit else { return false }

            for row in candidates {
                let tweet = tweets[row - 1]
                if prewarmPool[tweet.id] != nil { continue }
                if tableView.view(atColumn: 0, row: row, makeIfNecessary: false) != nil { continue }
                let cell = TimelineTweetCell()
                cell.identifier = TimelineTweetCell.identifier
                let width = max(1, clip.width)
                cell.frame = NSRect(x: 0, y: 0, width: width, height: max(1, rowHeights[row - 1]))
                cell.show(content(for: tweet))
                cell.layoutSubtreeIfNeeded()
                cell.hostedView?.layoutSubtreeIfNeeded()
                prewarmPool[tweet.id] = cell
                lastCellShownAt = CACurrentMediaTime()
                return true
            }
            return false
        }

        // Visible rows first; prepare nearby rows only when scrolling has settled.
        private func nextRowToMeasure() -> Int? {
            guard !tweets.isEmpty else { return nil }
            let clip = scrollView.contentView.bounds
            let visible = tableView.rows(in: clip)
            let firstVisible = max(0, visible.location - 1)
            let lastVisible = min(tweets.count - 1, max(firstVisible, visible.location + visible.length - 2))
            for index in stride(from: firstVisible, through: lastVisible, by: 1) where !heights.isMeasured(tweets[index]) {
                return index
            }
            guard !TimelineLiveScrollState.shared.isLiveScrolling else { return nil }
            for distance in 1...Self.lookAheadRows {
                let below = lastVisible + distance
                if below < tweets.count, !heights.isMeasured(tweets[below]) { return below }
                let above = firstVisible - distance
                if above >= 0, !heights.isMeasured(tweets[above]) { return above }
            }
            return nil
        }

        private func visibleTweetRows() -> [Int] {
            let visible = tableView.rows(in: scrollView.contentView.bounds)
            return (visible.location..<(visible.location + visible.length)).filter { $0 >= 1 && $0 <= tweets.count }
        }

        private func content(for tweet: Tweet) -> TimelineRowContent {
            TimelineRowContent(tweet: tweet, mediaColumnWidth: currentHeightContext().mediaColumnWidth)
        }

        // MARK: NSTableViewDataSource & Delegate

        func numberOfRows(in tableView: NSTableView) -> Int {
            tweets.isEmpty ? 0 : tweets.count + 2
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if row == 0 { return max(1, topSpacerHeight) }
            if row <= rowHeights.count { return rowHeights[row - 1] }
            return Self.footerHeight
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if row == 0 { return nil }
            if row > tweets.count {
                let cell = tableView.makeView(withIdentifier: TimelineFooterCell.identifier, owner: nil) as? TimelineFooterCell ?? {
                    let cell = TimelineFooterCell()
                    cell.identifier = TimelineFooterCell.identifier
                    return cell
                }()
                cell.show(active: isLoadingMore)
                return cell
            }
            let tweet = tweets[row - 1]
            if let cell = prewarmPool.removeValue(forKey: tweet.id) {
                cell.show(content(for: tweet))
                lastCellShownAt = CACurrentMediaTime()
                scheduleMeasuring()
                return cell
            }
            let cell = tableView.makeView(withIdentifier: TimelineTweetCell.identifier, owner: nil) as? TimelineTweetCell ?? {
                let cell = TimelineTweetCell()
                cell.identifier = TimelineTweetCell.identifier
                return cell
            }()
            cell.show(content(for: tweet))
            lastCellShownAt = CACurrentMediaTime()
            scheduleMeasuring()
            return cell
        }
    }
}
