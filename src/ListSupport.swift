//
//  ListSupport.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Scrolling screens are hosted in a SwiftUI List (backed by NSTableView on macOS), which scrolls far more
//  smoothly than ScrollView + LazyVStack.
//
//  Differences from ScrollView that this file handles:
//  - List has no titlebar safe area, so screens with floating bars add the titlebar height to their top spacer
//  - Rows are recycled, so a footer row's onAppear is not a reliable load-more trigger; scroll position is used
//  - Every row is padded up to the table's minimum height, so tiny standalone views (dividers) must be merged
//    into a neighbouring row
//

import SwiftUI
import AppKit

final class ListMetrics: ObservableObject {
    static let shared = ListMetrics()
    @Published var titlebarInset: CGFloat = 0

    func update(from window: NSWindow?) {
        guard let window = window else { return }
        let inset = max(0, window.frame.height - window.contentLayoutRect.height)
        if abs(titlebarInset - inset) > 0.5 {
            DispatchQueue.main.async { self.titlebarInset = inset }
        }
    }
}

// Calls `onNearBottom` when the reader is within 1.5 screens of the end of the list
final class NearBottomWatcher: ObservableObject {
    // Stable per screen, so rows that report the scroll view don't see a changed environment on every redraw
    let reporter = ListScrollReporter()
    private weak var scrollView: NSScrollView?
    private var observer: Any?
    private var onNearBottom: (() -> Void)?

    func attach(_ sv: NSScrollView, onNearBottom: (() -> Void)?) {
        self.onNearBottom = onNearBottom
        ListMetrics.shared.update(from: sv.window)
        guard scrollView !== sv else { return }
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = sv
        sv.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main
        ) { [weak self] _ in
            self?.check()
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func check() {
        guard let sv = scrollView, let doc = sv.documentView, let onNearBottom = onNearBottom else { return }
        let clip = sv.contentView.bounds
        if doc.frame.height - clip.maxY < clip.height * 1.5 {
            onNearBottom()
        }
    }
}

// Reports the List's scroll view from inside a row: a view inside a row can find its enclosing scroll view
// directly. The reporter is a stable object passed through the environment (a closure would look like a new value
// on every redraw and force every row to update).
final class ListScrollReporter {
    var onScrollView: ((NSScrollView) -> Void)?
    
    func report(_ sv: NSScrollView) {
        onScrollView?(sv)
    }
}

private struct ListScrollReporterKey: EnvironmentKey {
    static let defaultValue: ListScrollReporter? = nil
}

extension EnvironmentValues {
    var listScrollReporter: ListScrollReporter? {
        get { self[ListScrollReporterKey.self] }
        set { self[ListScrollReporterKey.self] = newValue }
    }
}

private struct ReportsListScrollView: ViewModifier {
    @Environment(\.listScrollReporter) private var reporter
    
    func body(content: Content) -> some View {
        if let reporter = reporter {
            content.background(ScrollViewAccessor { [weak reporter] sv in reporter?.report(sv) })
        } else {
            content
        }
    }
}

extension View {
    // Put on one row near the top of a ScrollContainer that has no top spacer, so the List's scroll view is found
    func reportsListScrollView() -> some View {
        modifier(ReportsListScrollView())
    }
    
    // A List row with no insets, separator, or background, so it looks exactly as it did in a LazyVStack
    func plainListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// A screen's scrolling content, in a List. `topSpacer` reserves room under floating bars; the titlebar height is
// added to it, because a List has no titlebar safe area.
struct ScrollContainer<Content: View>: View {
    var topSpacer: CGFloat? = nil
    var onScrollView: ((NSScrollView) -> Void)? = nil
    var onNearBottom: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    
    @ObservedObject private var metrics = ListMetrics.shared
    @StateObject private var watcher = NearBottomWatcher()
    
    var body: some View {
        let reporter = watcher.reporter
        reporter.onScrollView = { [watcher, onNearBottom, onScrollView] sv in
            watcher.attach(sv, onNearBottom: onNearBottom)
            onScrollView?(sv)
        }
        return List {
            Group {
                if let topSpacer = topSpacer {
                    Color.clear
                        .frame(height: topSpacer + metrics.titlebarInset)
                        .reportsListScrollView()
                }
                content()
            }
            .plainListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.listScrollReporter, reporter)
    }
}
