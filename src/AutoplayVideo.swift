//
//  AutoplayVideo.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Plays videos and GIFs in place on the timeline and post pages, muted and looping. Each video tile holds a marker view, and one
//  coordinator decides which of them are playing: rows are recycled and scrolled constantly, so leaving that to the
//  tiles would start and drop players on every frame of a scroll.
//

import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - Coordinator

final class AutoplayCoordinator {
    static let shared = AutoplayCoordinator()

    // One at a time, as on X: each player holds a network stream and a video decoder, and three of them made scrolling
    // visibly worse
    private static let maxPlaying = 1
    // A tile starts once this much of it is showing, so one peeking in at the edge stays still
    private static let minVisibleFraction: CGFloat = 0.5

    // How long after the last movement a scroll counts as finished
    private static let scrollSettleDelay: TimeInterval = 0.2

    private let views = NSHashTable<AutoplayVideoView>.weakObjects()
    private let watchedClipViews = NSHashTable<NSClipView>.weakObjects()
    private var observers: [AnyCancellable] = []
    private var isEvaluationScheduled = false
    private var lastScrollAt: CFTimeInterval = 0
    private var settleTimer: Timer?

    private init() {
        let trigger: () -> Void = { [weak self] in self?.setNeedsEvaluate() }
        observers = [
            // What decides the page in front, plus what moves the pages around: not the search text or the shortcut
            // badges, which change often and never affect playback
            observeChanges(of: {
                let nav = NavigationManager.shared
                _ = (nav.currentTab, nav.overlayStack.count, nav.sidebarExpanded, nav.isSearchActive)
            }, perform: trigger),
            LightboxManager.shared.objectWillChange.sink { _ in trigger() },
            VideoLightboxManager.shared.objectWillChange.sink { _ in trigger() },
            // Not only the timeline's scroll state: each kind of page tracks its own, and this has to cover them all
            NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification).sink { [weak self] note in
                self?.noteBoundsChange(of: note.object)
            },
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification).sink { _ in trigger() },
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification).sink { _ in trigger() }
        ]
    }

    func register(_ view: AutoplayVideoView) {
        views.add(view)
        setNeedsEvaluate()
    }

    func unregister(_ view: AutoplayVideoView) {
        views.remove(view)
        setNeedsEvaluate()
    }

    func watchScrolling(of clipView: NSClipView) {
        clipView.postsBoundsChangedNotifications = true
        watchedClipViews.add(clipView)
    }

    private func noteBoundsChange(of object: Any?) {
        guard let clipView = object as? NSClipView, watchedClipViews.contains(clipView) else { return }
        lastScrollAt = CACurrentMediaTime()
        guard settleTimer == nil else { return }
        let timer = Timer(timeInterval: Self.scrollSettleDelay, repeats: true) { [weak self] timer in
            guard let self = self, !self.isScrolling else { return }
            timer.invalidate()
            self.settleTimer = nil
            self.evaluate()
        }
        // Common modes: the default mode doesn't run while a scroll is being tracked
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private var isScrolling: Bool {
        CACurrentMediaTime() - lastScrollAt < Self.scrollSettleDelay
    }

    func setNeedsEvaluate() {
        guard !isEvaluationScheduled else { return }
        isEvaluationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isEvaluationScheduled = false
            self?.evaluate()
        }
    }

    // Only the page in front plays. The pages behind it stay in the window, so they would otherwise carry on unseen.
    private var frontScope: PeekScope {
        let nav = NavigationManager.shared
        if LightboxManager.shared.isPresented || VideoLightboxManager.shared.isPresented { return .none }
        if nav.hasOverlay { return .overlay(nav.overlayStack.count - 1) }
        switch nav.currentTab {
        case .home: return .timeline
        // The Videos tab has the screen to itself, so the timeline's tiles stop while it is in front
        case .videos: return .videos
        default: return .none
        }
    }

    private func evaluate() {
        // Moving pictures are what Reduce Motion asks an app not to start by itself
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            views.allObjects.forEach { $0.stop() }
            return
        }
        let front = frontScope
        let eligible = views.allObjects.filter { view in
            if view.scope != front { view.stop() }
            return view.scope == front
        }
        // Starting a player mid-scroll would hitch it. What is already playing carries on, and the rest is settled
        // when the scroll ends; a tile that leaves the window has stopped itself by then.
        guard !isScrolling else { return }

        let ranked = eligible
            .map { (view: $0, fraction: $0.visibleFraction) }
            .filter { $0.fraction >= Self.minVisibleFraction }
            // The post being read in the detail pane comes before anything in the timeline beside it
            .sorted { ($0.view.isPreferred ? 1 : 0, $0.fraction) > ($1.view.isPreferred ? 1 : 0, $1.fraction) }
        let chosen = ranked.prefix(Self.maxPlaying).map(\.view)
        for view in eligible where !chosen.contains(view) {
            // A page beside the one being watched stays loaded and paused (it is held), so arriving on it only has
            // to press play instead of starting a download
            if view.preloads { view.start() } else { view.stop() }
        }
        chosen.forEach { $0.start() }
    }
}

// MARK: - Player View

final class AutoplayVideoView: NSView {
    var media: TweetMedia? {
        didSet {
            guard media?.id != oldValue?.id else { return }
            stop()
            AutoplayCoordinator.shared.setNeedsEvaluate()
        }
    }
    var onPlayingChange: ((Bool) -> Void)?
    var scope: PeekScope = .none
    var isPreferred = false
    // The Videos tab plays with sound, shows the whole frame, and can be paused; a timeline tile is silent, cropped
    // like its thumbnail, and only ever started or stopped
    var isMuted = true {
        didSet {
            player?.isMuted = isMuted
            // Watching a video with sound is watching; a silent tile scrolling by is not
            player?.preventsDisplaySleepDuringVideoPlayback = !isMuted
        }
    }
    var showsWholeFrame = false {
        didSet { playerLayer?.videoGravity = showsWholeFrame ? .resizeAspect : .resizeAspectFill }
    }
    // Loaded ahead while not being watched, paused on its first frame; only the Videos tab's neighbouring pages, so at
    // most two wait like this
    var preloads = false
    // Seconds buffered ahead by a streamed Videos page: while it waits beside the one being watched, and while playing
    private static let heldBuffer: TimeInterval = 2
    private static let playingBuffer: TimeInterval = 6
    var isHeld = false {
        didSet {
            guard isHeld != oldValue, let player = player, let item = player.currentItem else { return }
            if scope == .videos, item.preferredForwardBufferDuration > 0 {
                item.preferredForwardBufferDuration = isHeld ? Self.heldBuffer : Self.playingBuffer
            }
            if isHeld { player.pause() } else { player.play() }
        }
    }

    // Made the first time this tile plays: most tiles scroll past without ever playing, and an AVPlayer takes up to a
    // millisecond to create, on the main thread, in the same frame the row is being built
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    // The tile whose address is being looked up, cleared if it is stopped before the answer arrives
    private var resolvingMediaId: String?
    private var readyObservation: NSKeyValueObservation?
    private var loopObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // Clicks belong to the tile's button underneath
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
        if let clipView = enclosingScrollView?.contentView { AutoplayCoordinator.shared.watchScrolling(of: clipView) }
        AutoplayCoordinator.shared.setNeedsEvaluate()
    }

    // How much of the tile is on screen, from 0 to 1. visibleRect alone can be wider than the view.
    var visibleFraction: CGFloat {
        guard let window = window, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor,
              bounds.width > 0, bounds.height > 0 else { return 0 }
        let visible = bounds.intersection(visibleRect)
        return (visible.width * visible.height) / (bounds.width * bounds.height)
    }

    func start() {
        guard player?.currentItem == nil, let media = media, resolvingMediaId != media.id else { return }
        resolvingMediaId = media.id
        // Finding the address checks the disk cache, so that happens away from the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = MediaHelpers.previewPlaybackURL(for: media)
            DispatchQueue.main.async {
                guard let self = self, self.resolvingMediaId == media.id else { return }
                self.resolvingMediaId = nil
                guard let url = url else { return }
                self.play(url)
            }
        }
    }

    private func play(_ url: URL) {
        let (player, playerLayer) = preparedPlayer()
        let item = AVPlayerItem(url: url)
        // Streamed in the Videos tab, a player would otherwise buffer as far ahead as it can and take the bandwidth
        // the next videos are being downloaded with, so each arrival would find its video still downloading. A page
        // waiting beside the one being watched needs only its opening seconds, enough to start the moment it arrives.
        if scope == .videos && !url.isFileURL {
            item.preferredForwardBufferDuration = isHeld ? Self.heldBuffer : Self.playingBuffer
        }
        player.replaceCurrentItem(with: item)
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self = self, self.player?.currentItem != nil else { return }
                self.playerLayer?.isHidden = false
                self.onPlayingChange?(true)
            }
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.player?.seek(to: .zero)
            if !self.isHeld { self.player?.play() }
        }
        if !isHeld { player.play() }
    }

    func stop() {
        resolvingMediaId = nil
        guard let player = player, player.currentItem != nil else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        readyObservation = nil
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        playerLayer?.isHidden = true
        onPlayingChange?(false)
    }

    private func preparedPlayer() -> (AVPlayer, AVPlayerLayer) {
        if let player = player, let playerLayer = playerLayer { return (player, playerLayer) }
        let player = AVPlayer()
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = !isMuted
        let playerLayer = AVPlayerLayer()
        playerLayer.player = player
        // Same crop as the thumbnail underneath, which stays visible until the first frame is ready
        playerLayer.videoGravity = showsWholeFrame ? .resizeAspect : .resizeAspectFill
        playerLayer.isHidden = true
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
        self.player = player
        self.playerLayer = playerLayer
        return (player, playerLayer)
    }
}

// MARK: - SwiftUI

struct AutoplayVideoRepresentable: NSViewRepresentable {
    let media: TweetMedia
    let scope: PeekScope
    let isPreferred: Bool
    var isMuted = true
    var showsWholeFrame = false
    var isHeld = false
    var preloads = false
    let onPlayingChange: (Bool) -> Void

    func makeNSView(context: Context) -> AutoplayVideoView {
        let view = AutoplayVideoView()
        configure(view)
        AutoplayCoordinator.shared.register(view)
        return view
    }

    func updateNSView(_ view: AutoplayVideoView, context: Context) {
        // Which page is preferred moves with every swipe, and the coordinator only looks when asked
        let preferenceChanged = view.isPreferred != isPreferred || view.preloads != preloads
        configure(view)
        if preferenceChanged { AutoplayCoordinator.shared.setNeedsEvaluate() }
    }

    private func configure(_ view: AutoplayVideoView) {
        view.isMuted = isMuted
        view.showsWholeFrame = showsWholeFrame
        view.isHeld = isHeld
        view.preloads = preloads
        view.media = media
        view.scope = scope
        view.isPreferred = isPreferred
        view.onPlayingChange = onPlayingChange
    }

    static func dismantleNSView(_ view: AutoplayVideoView, coordinator: ()) {
        view.stop()
        AutoplayCoordinator.shared.unregister(view)
    }
}

// Which pages play videos by themselves; the rest show the play icon and wait for a click
private struct AllowsVideoAutoplayKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PrefersVideoAutoplayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var prefersVideoAutoplay: Bool {
        get { self[PrefersVideoAutoplayKey.self] }
        set { self[PrefersVideoAutoplayKey.self] = newValue }
    }

    var allowsVideoAutoplay: Bool {
        get { self[AllowsVideoAutoplayKey.self] }
        set { self[AllowsVideoAutoplayKey.self] = newValue }
    }
}

// Which video is playing rather than a flag, so a reused table cell shows the next video's play icon straight away
private final class AutoplayState: ObservableObject {
    @Published var playingMediaId: String?
}

// What sits over a video's thumbnail: the player where autoplay applies, then the play icon and duration. The icon
// makes way once the video is moving, since a click on it still opens the full player.
struct VideoTileOverlay: View {
    let media: TweetMedia

    @Environment(\.peekScope) private var scope
    @Environment(\.allowsVideoAutoplay) private var allowsAutoplay
    @Environment(\.prefersVideoAutoplay) private var prefersAutoplay
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var state = AutoplayState()

    var body: some View {
        ZStack {
            if allowsAutoplay, theme.autoplayMedia, media.videoInfo != nil {
                AutoplayVideoRepresentable(media: media, scope: scope, isPreferred: prefersAutoplay) { [state, id = media.id] playing in
                    // Later, because a cell handed a new video stops the old one while SwiftUI is updating it
                    DispatchQueue.main.async {
                        let playingId = playing ? id : nil
                        if state.playingMediaId != playingId { state.playingMediaId = playingId }
                    }
                }
            }
            VideoBadgeOverlay(media: media, showsPlayIcon: state.playingMediaId != media.id)
        }
    }
}
