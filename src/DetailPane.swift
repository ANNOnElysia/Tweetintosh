//
//  DetailPane.swift
//  Tweetintosh - Headless Data-driven Client
//
//  In a wide window, Home has three columns like Mail: the sidebar, the timeline, and the post being read beside it, so
//  reading a post doesn't lose the place in the timeline. Narrower windows open posts over everything, as full pages.
//

import SwiftUI
import Combine

// Published apart from the stack: the columns depend only on this, so opening a post doesn't touch the timeline's views
final class DetailPaneLayout: ObservableObject {
    @Published var isAvailable = false
}

final class DetailPane: ObservableObject {
    static let shared = DetailPane()

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let tweet: Tweet
        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
    }

    // The three columns need this much with the sidebar open, whatever share of a small screen that is
    private static let minimumWindowWidth: CGFloat = 1094

    let layout = DetailPaneLayout()
    var isAvailable: Bool { layout.isAvailable }
    // The posts opened in the pane, newest last, so a reply opened from a post can go back to it
    @Published private(set) var stack: [Entry] = []

    var isOpen: Bool { isAvailable && !stack.isEmpty }

    // Answers whether that changed anything
    func updateAvailability(windowWidth: CGFloat, screenWidth: CGFloat) -> Bool {
        let available = windowWidth >= max(screenWidth * 2 / 3, Self.minimumWindowWidth)
        guard available != isAvailable else { return false }
        layout.isAvailable = available
        return true
    }

    // A post chosen from inside the pane stacks on the one showing; one from the timeline starts afresh
    func open(_ tweet: Tweet, fromPane: Bool) {
        guard stack.last?.tweet.id != tweet.id else { return }
        if fromPane {
            stack.append(Entry(tweet: tweet))
        } else {
            stack = [Entry(tweet: tweet)]
        }
    }

    func goBack() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }

    // Hands over what was open, for when the window has become too narrow to show it here
    func takeStack() -> [Tweet] {
        defer { stack = [] }
        return stack.map(\.tweet)
    }

    // Takes over posts that were open as full pages, for when the window has become wide enough to show them here
    func adopt(_ tweets: [Tweet]) {
        stack = tweets.map { Entry(tweet: $0) }
    }

    func clear() {
        stack = []
    }
}

private struct IsInDetailPaneKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MediaColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var isInDetailPane: Bool {
        get { self[IsInDetailPaneKey.self] }
        set { self[IsInDetailPaneKey.self] = newValue }
    }

    // How wide media may be in this column
    var mediaColumnWidth: CGFloat? {
        get { self[MediaColumnWidthKey.self] }
        set { self[MediaColumnWidthKey.self] = newValue }
    }
}

// MARK: - Columns

// The timeline is held to a comfortable reading width. It keeps the same place in the view tree whether or not the pane
// is showing, so resizing the window doesn't rebuild it and lose the scroll position.
struct HomeColumns<Timeline: View>: View {
    let sidebarExpanded: Bool
    @ViewBuilder let timeline: () -> Timeline
    @ObservedObject private var layout = DetailPane.shared.layout

    // Alone, the timeline stops at a reading width. Beside the pane it takes the larger share, and the pane fills what is
    // left, so the columns meet the window's edges with nothing blank around them.
    private static var aloneWidth: CGFloat { 760 }
    private static var besidePaneMaxWidth: CGFloat { 900 }
    private static var paneMinWidth: CGFloat { 380 }
    // Margins, avatar and spacing beside a post's media
    private static var mediaInset: CGFloat { 82 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let timelineWidth = layout.isAvailable
                ? min(Self.besidePaneMaxWidth, width * 0.6, width - Self.paneMinWidth)
                : min(Self.aloneWidth, width)
            let paneWidth = width - timelineWidth
            HStack(spacing: 0) {
                timeline()
                    .frame(width: timelineWidth)
                    .environment(\.mediaColumnWidth, timelineWidth - Self.mediaInset)
                if layout.isAvailable {
                    Rectangle()
                        .fill(ThemeManager.divider)
                        .frame(width: 0.5)
                        .ignoresSafeArea()
                    DetailPaneColumn(sidebarExpanded: sidebarExpanded)
                        .frame(width: paneWidth)
                        .environment(\.mediaColumnWidth, paneWidth - Self.mediaInset)
                }
            }
            .frame(width: width, height: proxy.size.height)
        }
    }
}

// Every page stays mounted, with only the top one receiving input. Going back then needs no reload and keeps the scroll
// position, and opening a post doesn't rebuild the notifications table on closing it, which was most of the cost.
private struct DetailPaneColumn: View {
    let sidebarExpanded: Bool
    @ObservedObject private var pane = DetailPane.shared

    var body: some View {
        ZStack {
            NotificationsGlanceView()
                .modifier(PaneLayer(isFront: pane.stack.isEmpty))
            ForEach(Array(pane.stack.enumerated()), id: \.element.id) { index, entry in
                TweetDetailView(tweet: entry.tweet, backIcon: index > 0 ? "chevron.left" : "xmark") {
                    pane.goBack()
                }
                .environment(\.allowsVideoAutoplay, true)
                .environment(\.prefersVideoAutoplay, true)
                .modifier(PaneLayer(isFront: index == pane.stack.count - 1))
            }
        }
        .environment(\.isInDetailPane, true)
        // The floating bar sits across the top of the window while the sidebar is closed
        .padding(.top, sidebarExpanded ? 0 : 52)
    }
}

// A page underneath is covered by the opaque one on top rather than faded out: SwiftUI stops rendering anything at zero
// opacity, so bringing it back would rebuild its views and redraw its text. It also leaves the front scope, which stops
// its videos and keeps deep presses from finding it.
private struct PaneLayer: ViewModifier {
    let isFront: Bool

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isFront)
            .accessibilityHidden(!isFront)
            .environment(\.peekScope, isFront ? .timeline : .paneHidden)
    }
}

// MARK: - Open Post Highlight

// Subscribes once and publishes only when this row's answer changes, so opening a post updates the row losing the highlight
// and the one gaining it. Subscribing from the view would start over at every redraw, and each start publishes.
private final class OpenPostHighlightState: ObservableObject {
    @Published private(set) var isOpen = false
    private var subscription: AnyCancellable?

    init(tweetId: String) {
        subscription = DetailPane.shared.$stack
            .map { $0.first?.tweet.id == tweetId }
            .removeDuplicates()
            .sink { [weak self] open in
                if self?.isOpen != open { self?.isOpen = open }
            }
    }
}

struct HighlightsOpenPost: ViewModifier {
    @StateObject private var state: OpenPostHighlightState
    @ObservedObject private var theme = ThemeManager.shared

    init(tweetId: String) {
        _state = StateObject(wrappedValue: OpenPostHighlightState(tweetId: tweetId))
    }

    func body(content: Content) -> some View {
        content.overlay {
            if state.isOpen {
                Rectangle()
                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.07 : 0.10))
                    .allowsHitTesting(false)
            }
        }
    }
}
