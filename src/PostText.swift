//
//  PostText.swift
//  Tweetintosh - Headless Data-driven Client
//
//  A post's body as a real AppKit text view, where the timeline's own Text could not do the job. X's web client lets
//  a post be opened by clicking its text, lets a drag select that text instead, and treats the click that clears a
//  selection as just clearing it. SwiftUI's selectable Text keeps the selection to itself, so the row could not tell
//  those three clicks apart; an NSTextView reports its selection, so it can.
//

import AppKit
import SwiftUI

// MARK: - Rendering

enum PostTextRenderer {
    static func font(size: CGFloat) -> NSFont {
        let theme = ThemeManager.shared
        if theme.fontType == .mincho {
            return NSFont(name: theme.activeSerifFontName, size: size + 0.5) ?? .systemFont(ofSize: size)
        }
        return .systemFont(ofSize: size)
    }

    // The same text, links, mentions and colours a post row shows in SwiftUI
    static func attributed(_ tweet: Tweet, fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let text = NSMutableAttributedString(string: tweet.displayBodyText, attributes: [
            .font: font(size: fontSize),
            .foregroundColor: NSColor(ThemeManager.primaryText),
            .paragraphStyle: paragraph
        ])

        let accent = NSColor(ThemeManager.accent)
        for link in tweet.displayLinks {
            guard let url = URL(string: link.url) else { continue }
            let range = NSRange(location: link.location, length: link.length)
            guard NSMaxRange(range) <= text.length else { continue }
            text.addAttributes([.link: url, .foregroundColor: accent], range: range)
        }
        for mention in TweetText.mentionRanges(in: tweet.displayBodyText, excluding: tweet.displayLinks) {
            guard let url = TweetText.mentionURL(mention.name),
                  NSMaxRange(mention.range) <= text.length else { continue }
            text.addAttributes([.link: url, .foregroundColor: accent], range: mention.range)
        }
        return text
    }

    // The height the same text lays out to at a width, measured with TextKit so the row and its table agree on it
    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }
}

// MARK: - Text View

// What a click on the body does, as X's web client does it: with no selection it opens the post, and the click that
// ends a selection only ends it. Links and @mentions open their own targets and never the post.
final class PostTextLabelView: NSTextView, NSTextViewDelegate {
    var onOpen: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?

    private var hadSelectionAtPress = false
    private var openedLinkOnThisClick = false
    private var clickFinished = false

    // NSTextView tracks the press inside mouseDown and may not call mouseUp at all, so the answer is settled after
    // the press returns, and mouseUp covers the paths where it doesn't track.
    override func mouseDown(with event: NSEvent) {
        hadSelectionAtPress = selectedRange().length > 0
        openedLinkOnThisClick = false
        clickFinished = false
        super.mouseDown(with: event)
        finishClick(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        finishClick(at: event.locationInWindow)
    }

    private func finishClick(at windowPoint: NSPoint) {
        guard !clickFinished else { return }
        clickFinished = true
        let hadSelection = hadSelectionAtPress
        hadSelectionAtPress = false
        if openedLinkOnThisClick {
            openedLinkOnThisClick = false
            return
        }
        // A drag leaves a selection behind, and the click that cleared one is answered by that alone
        guard !hadSelection, selectedRange().length == 0 else { return }
        // The text view normally reports a link through its delegate first; this keeps a click on one from also
        // opening the post if it didn't
        if let url = link(at: convert(windowPoint, from: nil)) {
            openLink(url)
            return
        }
        onOpen?()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL else { return false }
        openedLinkOnThisClick = true
        openLink(url)
        return true
    }

    // A press can hand the view a frame SwiftUI computed before a width was known; a non-finite one would make the
    // text system assert, so it never reaches the text container.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width.isFinite ? newSize.width : 0,
                                  height: newSize.height.isFinite ? newSize.height : 0))
    }

    // MARK: Pointer

    // A post in the timeline is one click target, so its card keeps the hand even over the text, as X's web client
    // does. The text is still selectable; only the pointer does not change. The cursor rectangles are replaced with
    // one hand rectangle, and the tracking area answers every move as well: the text view would otherwise put its
    // I-beam back after the cursor enters.
    private var handTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let handTrackingArea { removeTrackingArea(handTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        handTrackingArea = area
        // Ask for the rectangles again now that any the text view laid down while setting up are known
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        // A table can ask while the cell has no finite visible rect yet; an infinite one makes AppKit assert
        let rect = bounds.intersection(visibleRect)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, !rect.isEmpty else { return }
        addCursorRect(rect, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    private func openLink(_ url: URL) {
        guard let onOpenURL else { return }
        onOpenURL(url)
    }

    private func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let storage = textStorage else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer,
                                             fractionOfDistanceThroughGlyph: &fraction)
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}

// MARK: - SwiftUI Bridge

struct PostText: NSViewRepresentable {
    let tweet: Tweet
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let onOpen: () -> Void

    // Everything the attributed string is built from, so a row that redraws for a like doesn't lay it out again
    struct Key: Equatable {
        let text: String
        let links: [DisplayLink]
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let fontType: String
        let language: String
        let isLight: Bool
        let isMild: Bool
        let themeColor: String
    }

    private var key: Key {
        let theme = ThemeManager.shared
        return Key(text: tweet.displayBodyText, links: tweet.displayLinks, fontSize: fontSize,
                   lineSpacing: lineSpacing, fontType: theme.fontType.rawValue,
                   language: LocalizationManager.shared.currentLanguage.rawValue,
                   isLight: theme.isLight, isMild: theme.isMild, themeColor: theme.themeColor.rawValue)
    }

    final class Coordinator {
        var key: Key?
        var text: NSAttributedString?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PostTextLabelView {
        let view = PostTextLabelView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.focusRingType = .none
        view.allowsUndo = false
        view.isAutomaticLinkDetectionEnabled = false
        view.delegate = view
        view.onOpenURL = { url in
            if TweetText.isInternal(url) {
                _ = TweetText.open(url)
            } else if !PeekCoordinator.shared.suppressesActivation {
                NSWorkspace.shared.open(url)
            }
        }
        return view
    }

    func updateNSView(_ view: PostTextLabelView, context: Context) {
        view.onOpen = onOpen
        // The colour comes from the theme, and setting it here keeps a link looking the same as in the SwiftUI text
        // elsewhere in the app rather than AppKit's default blue and underline
        view.linkTextAttributes = [.foregroundColor: NSColor(ThemeManager.accent)]
        let key = key
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        let text = PostTextRenderer.attributed(tweet, fontSize: fontSize, lineSpacing: lineSpacing)
        context.coordinator.text = text
        view.textStorage?.setAttributedString(text)
    }

    // The height is TextKit's, not the view's, so the table measures and the row draws from the same answer
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PostTextLabelView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        // SwiftUI offers infinity when it asks for an ideal size; laying out to that would hand it a frame AppKit
        // cannot draw or place a cursor in.
        guard width.isFinite, width > 0 else { return nil }
        let text = context.coordinator.text ?? PostTextRenderer.attributed(tweet, fontSize: fontSize,
                                                                           lineSpacing: lineSpacing)
        return CGSize(width: width, height: PostTextRenderer.height(of: text, width: width))
    }
}
