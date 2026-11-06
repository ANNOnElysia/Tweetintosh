//
//  DetailPane.swift
//  Tweetintosh - Headless Data-driven Client
//
//  In a wide window, Home has three columns like Mail: the sidebar, the timeline, and the post being read beside it, so
//  reading a post doesn't lose the place in the timeline. Narrower windows open posts over everything, as full pages.
//

import SwiftUI

final class DetailPane: ObservableObject {
    static let shared = DetailPane()

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let tweet: Tweet
        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
    }

    // The three columns need this much with the sidebar open, whatever share of a small screen that is
    private static let minimumWindowWidth: CGFloat = 1094

    @Published private(set) var isAvailable = false
    // The posts opened in the pane, newest last, so a reply opened from a post can go back to it
    @Published private(set) var stack: [Entry] = []

    var isOpen: Bool { isAvailable && !stack.isEmpty }

    // Answers whether that changed anything
    func updateAvailability(windowWidth: CGFloat, screenWidth: CGFloat) -> Bool {
        let available = windowWidth >= max(screenWidth * 2 / 3, Self.minimumWindowWidth)
        guard available != isAvailable else { return false }
        isAvailable = available
        return true
    }

    // A post chosen from inside the pane stacks on the one showing; one from the timeline starts afresh
    func open(_ tweet: Tweet, fromPane: Bool) {
        guard stack.last?.tweet.id != tweet.id else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if fromPane {
                stack.append(Entry(tweet: tweet))
            } else {
                stack = [Entry(tweet: tweet)]
            }
        }
    }

    func goBack() {
        guard !stack.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            _ = stack.removeLast()
        }
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
    @ViewBuilder let timeline: () -> Timeline
    @ObservedObject private var pane = DetailPane.shared

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
            let timelineWidth = pane.isAvailable
                ? min(Self.besidePaneMaxWidth, width * 0.6, width - Self.paneMinWidth)
                : min(Self.aloneWidth, width)
            let paneWidth = width - timelineWidth
            HStack(spacing: 0) {
                timeline()
                    .frame(width: timelineWidth)
                    .environment(\.mediaColumnWidth, timelineWidth - Self.mediaInset)
                if pane.isAvailable {
                    Rectangle()
                        .fill(ThemeManager.divider)
                        .frame(width: 0.5)
                        .ignoresSafeArea()
                    DetailPaneColumn()
                        .frame(width: paneWidth)
                        .environment(\.mediaColumnWidth, paneWidth - Self.mediaInset)
                }
            }
            .frame(width: width, height: proxy.size.height)
        }
    }
}

private struct DetailPaneColumn: View {
    @ObservedObject private var pane = DetailPane.shared
    @ObservedObject private var nav = NavigationManager.shared

    var body: some View {
        Group {
            if let entry = pane.stack.last {
                TweetDetailView(
                    tweet: entry.tweet,
                    backIcon: pane.stack.count > 1 ? "chevron.left" : "xmark"
                ) {
                    pane.goBack()
                }
                .id(entry.id)
                .environment(\.allowsVideoAutoplay, true)
                .environment(\.prefersVideoAutoplay, true)
                .transition(.opacity)
            } else {
                NotificationsGlanceView()
                    .transition(.opacity)
            }
        }
        .environment(\.isInDetailPane, true)
        .environment(\.peekScope, .timeline)
        // The floating bar sits across the top of the window while the sidebar is closed
        .padding(.top, nav.sidebarExpanded ? 0 : 52)
    }
}

// MARK: - Open Post Highlight

// A modifier of its own, so opening a post updates this and not every row of the timeline
struct HighlightsOpenPost: ViewModifier {
    let tweetId: String
    @ObservedObject private var pane = DetailPane.shared
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        content.overlay {
            if pane.isOpen && pane.stack.first?.tweet.id == tweetId {
                Rectangle()
                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.07 : 0.10))
                    .allowsHitTesting(false)
            }
        }
    }
}
