//
//  DetailPane.swift
//  Tweetintosh - Headless Data-driven Client
//
//  In a wide window, Home has three columns like Mail: the sidebar, the timeline, and the post being read beside it, so
//  reading a post doesn't lose the place in the timeline. Narrower windows open posts over everything, as full pages.
//

import SwiftUI
import AppKit

// Published apart from the stack: the columns depend only on this, so opening a post doesn't touch the timeline's views
final class DetailPaneLayout: ObservableObject {
    private static let collapsedKey = "Tweetintosh_DetailPaneCollapsed"
    private static let widthKey = "Tweetintosh_DetailPaneWidth"

    // The pane is showing: the window is wide enough and the reader hasn't hidden it
    @Published fileprivate(set) var isAvailable = false
    // Wide enough for three columns, whether or not the pane is hidden
    @Published fileprivate(set) var fitsWindow = false
    @Published fileprivate(set) var isCollapsed = UserDefaults.standard.bool(forKey: collapsedKey)
    // The width the reader dragged the pane to; nil keeps the default share. Kept while the window is too narrow for
    // it, so it comes back when the window is wide enough again.
    @Published var paneWidth: CGFloat? = {
        let stored = UserDefaults.standard.double(forKey: widthKey)
        return stored > 0 ? CGFloat(stored) : nil
    }()

    fileprivate func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
    }

    // Saved once a drag ends rather than on every step of it
    func saveWidth() {
        if let paneWidth {
            UserDefaults.standard.set(Double(paneWidth), forKey: Self.widthKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.widthKey)
        }
    }
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

    var fitsWindow: Bool { layout.fitsWindow }
    var isCollapsed: Bool { layout.isCollapsed }

    // Answers whether the pane appeared or went away
    func updateAvailability(windowWidth: CGFloat, screenWidth: CGFloat) -> Bool {
        let fits = windowWidth >= max(screenWidth * 2 / 3, Self.minimumWindowWidth)
        if fits != layout.fitsWindow { layout.fitsWindow = fits }
        return refreshAvailability()
    }

    // Hides or shows the pane by the reader's choice; answers whether the pane appeared or went away
    func setCollapsed(_ collapsed: Bool) -> Bool {
        guard collapsed != layout.isCollapsed else { return false }
        layout.setCollapsed(collapsed)
        return refreshAvailability()
    }

    private func refreshAvailability() -> Bool {
        let available = layout.fitsWindow && !layout.isCollapsed
        guard available != layout.isAvailable else { return false }
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
    @ViewBuilder let timeline: () -> Timeline
    @ObservedObject private var layout = DetailPane.shared.layout
    @ObservedObject private var theme = ThemeManager.shared

    // Alone, the timeline stops at a reading width. Beside the pane it takes the larger share, and the pane fills what is
    // left, so the columns meet the window's edges with nothing blank around them.
    private static var aloneWidth: CGFloat { 760 }
    private static var besidePaneMaxWidth: CGFloat { 900 }
    static var paneMinWidth: CGFloat { 380 }
    static var timelineMinWidth: CGFloat { 520 }
    // Margins, avatar and spacing beside a post's media
    private static var mediaInset: CGFloat { 82 }

    /// How wide the timeline column is in a window of `width`; with no pane beside it, the column is centred.
    static func timelineWidth(in width: CGFloat, paneAvailable: Bool) -> CGFloat {
        guard paneAvailable else { return min(aloneWidth, width) }
        if let chosen = DetailPane.shared.layout.paneWidth, width - timelineMinWidth >= paneMinWidth {
            return width - clampedPaneWidth(chosen, in: width)
        }
        return min(besidePaneMaxWidth, width * 0.6, width - paneMinWidth)
    }

    // The pane keeps at least its minimum and leaves the timeline at least its own
    static func clampedPaneWidth(_ width: CGFloat, in windowWidth: CGFloat) -> CGFloat {
        min(max(width, paneMinWidth), max(windowWidth - timelineMinWidth, paneMinWidth))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let timelineWidth = Self.timelineWidth(in: width, paneAvailable: layout.isAvailable)
            let paneWidth = width - timelineWidth
            HStack(spacing: 0) {
                timeline()
                    .frame(width: timelineWidth)
                    .environment(\.mediaColumnWidth, timelineWidth - Self.mediaInset)
                if layout.isAvailable {
                    PaneSlideIn {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(ThemeManager.divider)
                                .frame(width: 0.5)
                                .ignoresSafeArea()
                                .overlay { PaneDivider(windowWidth: width) }
                                .zIndex(1)
                            DetailPaneColumn()
                                .frame(width: paneWidth)
                                .environment(\.mediaColumnWidth, paneWidth - Self.mediaInset)
                        }
                    }
                }
            }
            .frame(width: width, height: proxy.size.height)
            .coordinateSpace(name: PaneDivider.space)
            .overlay(alignment: .topTrailing) {
                // Brings the hidden pane back, at the top bar's height, opposite the sidebar button
                if layout.fitsWindow && layout.isCollapsed {
                    PaneToggleButton(style: .bar)
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Resizing and Hiding

// The line between the timeline and the pane, with an 8-point band either side of it to drag. The pointer becomes the
// column-resize arrows over it; a double-click puts the pane back to its default width.
private struct PaneDivider: View {
    static let space = "HomeColumns"
    let windowWidth: CGFloat
    @ObservedObject private var layout = DetailPane.shared.layout

    var body: some View {
        Color.clear
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        layout.paneWidth = HomeColumns<EmptyView>.clampedPaneWidth(windowWidth - value.location.x,
                                                                                  in: windowWidth)
                    }
                    .onEnded { _ in layout.saveWidth() }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { layout.paneWidth = nil }
                layout.saveWidth()
            }
            .accessibilityHidden(true)
    }
}

// Hides the pane, or brings it back. In the pane it matches the round buttons at the top of a post; over the timeline
// it matches the sidebar button in the top bar.
struct PaneToggleButton: View {
    enum Style { case round, bar }
    let style: Style
    @ObservedObject private var layout = DetailPane.shared.layout
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        let title = loc.t(layout.isCollapsed ? "menu_show_pane" : "menu_hide_pane")
        Button { NavigationManager.shared.toggleDetailPane() } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ThemeManager.primaryText)
                .frame(width: style == .round ? 36 : nil, height: style == .round ? 36 : 32)
                .padding(.horizontal, style == .bar ? 8 : 0)
                .background { background }
        }
        .buttonStyle(.target)
        .help("\(title) (⌥⌘I)")
        .accessibilityLabel(title)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .bar:
            Capsule().fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
        case .round:
            if theme.useLiquidGlass, #available(macOS 26.0, *) {
                Circle()
                    .fill(theme.isLight ? Color.white.opacity(0.68) : Color.black.opacity(0.24))
                    .tweetGlass(.regular.interactive(), in: Circle())
            } else {
                Circle()
                    .fill(theme.isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.45))
                    .overlay(Circle().stroke(theme.isLight ? Color(hex: "#DED9CB").opacity(0.85) : Color.white.opacity(0.22),
                                             lineWidth: 0.75))
            }
        }
    }
}

private final class PaneArrival: ObservableObject {
    @Published var hasLanded = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

// Glides and fades the pane in when it arrives, and not at all under Reduce Motion. It starts on screen and almost
// transparent: a table builds its rows only once it is on screen, and SwiftUI doesn't render anything at zero opacity, so
// sliding from the window's edge stalls at the moment it comes into view and the slide is over by the time it draws.
private struct PaneSlideIn<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @StateObject private var arrival = PaneArrival()

    var body: some View {
        content()
            .opacity(arrival.hasLanded ? 1 : 0.01)
            .offset(x: arrival.hasLanded ? 0 : 56)
            .onAppear {
                guard !arrival.hasLanded else { return }
                // Long enough for the first layout, which runs on the display cycle after this
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.95)) { arrival.hasLanded = true }
                }
            }
    }
}

// Every page stays mounted, with only the top one receiving input. Going back then needs no reload and keeps the scroll
// position, and opening a post doesn't rebuild the notifications table on closing it, which was most of the cost.
// It runs the full height of the window whatever the sidebar does: the top bar only ever floats over the timeline
// column, never over the pane.
private struct DetailPaneColumn: View {
    @ObservedObject private var pane = DetailPane.shared

    var body: some View {
        ZStack {
            NotificationsGlanceView()
                .overlay(alignment: .topTrailing) {
                    PaneToggleButton(style: .round)
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                }
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
