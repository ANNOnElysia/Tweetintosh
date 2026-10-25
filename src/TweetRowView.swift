//
//  TweetRowView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI

struct TweetRowView: View {
    let tweet: Tweet
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Clickable Area: Repost Header, Avatar, Author Info, Tweet Text, Media & Quote
            VStack(alignment: .leading, spacing: 0) {
                // 1. Repost Header (with standard native spacing & alignment)
                if tweet.isRetweet, let rtBy = tweet.retweetedBy {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(ThemeManager.secondaryText)
                        
                        Text("\(rtBy) \(loc.t("retweet"))")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(ThemeManager.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.leading, 50) // Aligns with author name column
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                } else {
                    Spacer().frame(height: 12)
                }
                
                // 2. Main Content Row (Avatar + Text/Media Column)
                HStack(alignment: .top, spacing: 10) {
                    // Author Avatar
                    CachedAsyncImage(urlString: tweet.author.avatarUrl, targetSize: CGSize(width: 40, height: 40))
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                        .peekable(.profile(tweet.author))
                    
                    // Content Column
                    VStack(alignment: .leading, spacing: 6) {
                        // Header: Author Name, Verified Badge, Handle, Dot, Relative Time
                        HStack(alignment: .center, spacing: 4) {
                            Text(tweet.author.name)
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                                .lineLimit(1)
                                .peekable(.profile(tweet.author))
                            
                            if tweet.author.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeManager.accent)
                            }
                            
                            Text(tweet.author.formattedHandle)
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                                .lineLimit(1)
                                .peekable(.profile(tweet.author))
                            
                            Text("·")
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                            
                            Text(tweet.relativeTime)
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                            
                            Spacer()
                            
                            if tweet.isPromoted {
                                AdBadgeView()
                            }
                        }
                        
                        // Reply Context Subheader (Consistent with official X logic)
                        if let replyContext = tweet.replyContextText {
                            Text(replyContext)
                                .font(.system(size: 12.5))
                                .foregroundColor(ThemeManager.secondaryText)
                                .lineLimit(1)
                        }
                        
                        // Tweet Body Text (Clean text with leading reply mentions & trailing media t.co URLs stripped)
                        if !tweet.displayBodyText.isEmpty {
                            bodyText
                                .font(theme.tweetFont(size: 14.5))
                                .lineSpacing(theme.lineSpacing())
                                .foregroundColor(ThemeManager.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                // A deep press on a link previews it; its release must not also open the browser
                                .environment(\.openURL, OpenURLAction { url in
                                    PeekCoordinator.shared.suppressesActivation ? .handled : .systemAction(url)
                                })
                                .peekable { [tweet] point, size in
                                    PeekTextLinks.link(at: point, size: size, text: tweet.displayBodyText, links: tweet.displayLinks)
                                        .map { PeekTarget.link($0) }
                                }
                        }
                        
                        // Media Photo / Video Grid
                        if !tweet.media.isEmpty {
                            ImageGridView(mediaList: tweet.media, tweet: tweet)
                                .padding(.top, 2)
                        }
                        
                        // Embedded Quoted Tweet (if any)
                        if let quoted = tweet.quoted {
                            QuotedTweetCard(tweet: quoted)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NavigationManager.shared.openTweetDetail(tweet)
            }
            
            // 3. Interaction Metrics Bar: Impressions (Views) on Left, Actions on Right
            // Kept outside content onTapGesture to allow direct, uninhibited interaction with buttons & menus
            TweetActionBar(tweet: tweet)
                .padding(.leading, 66) // Aligns with text column (16 horizontal padding + 40 avatar + 10 spacing)
                .padding(.trailing, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // 4. Subtle Row Divider
            Divider()
                .background(ThemeManager.divider)
        }
        .background(ThemeManager.background)
    }
    
    // Body text with links shown by their display URL in the accent colour; clicking one opens it in the browser
    private var bodyText: Text {
        guard !tweet.displayLinks.isEmpty else { return Text(tweet.displayBodyText) }
        let body = tweet.displayBodyText
        var attributed = AttributedString(body)
        for link in tweet.displayLinks {
            guard let range = Range(NSRange(location: link.location, length: link.length), in: body),
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = ThemeManager.accent
            attributed[attrRange].link = URL(string: link.url)
        }
        return Text(attributed)
    }
    
    private func metricItem(icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
            if count > 0 {
                Text(formatCount(count))
                    .font(.system(size: 12))
            }
        }
        .foregroundColor(ThemeManager.secondaryText)
    }
    
    private func openTweetOnWeb() {
        let urlStr = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}

private func formatCount(_ n: Int) -> String {
    if n >= 1_000_000 {
        return String(format: "%.1fM", Double(n) / 1_000_000.0)
    } else if n >= 1_000 {
        return String(format: "%.1fK", Double(n) / 1_000.0)
    }
    return "\(n)"
}

// MARK: - Hover Reader
// Keeps hover in its own state object so hovering one action redraws only that action, not the whole tweet row.
private final class HoverState: ObservableObject {
    @Published var isHovered = false
}

private struct HoverReader<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @StateObject private var state = HoverState()
    
    var body: some View {
        content(state.isHovered)
            .onHover { state.isHovered = $0 }
    }
}

private final class LikeAnimationState: ObservableObject {
    @Published var scale: CGFloat = 1.0
}

// MARK: - Tweet Action Bar (Views count + Reply, Repost, Like, Bookmark)
private struct TweetActionBar: View {
    let tweet: Tweet
    @ObservedObject var loc = LocalizationManager.shared
    @StateObject private var like = LikeAnimationState()
    
    var body: some View {
        HStack(alignment: .center) {
            // Left: Impressions / Views Count
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11.5))
                Text(formatCount(tweet.viewCount ?? 0))
                    .font(.system(size: 11.5))
            }
            .foregroundColor(ThemeManager.secondaryText.opacity(0.85))
            .help(loc.t("views"))
            
            Spacer()
            
            // Right: Interaction Metrics (Reply, Repost, Like, Bookmark)
            HStack(spacing: 24) {
                // 1. Reply
                HoverReader { hovered in
                    Button(action: { NavigationManager.shared.openReply(to: tweet) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12))
                            if tweet.replyCount > 0 {
                                Text(formatCount(tweet.replyCount))
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundColor(hovered ? Color(red: 0.114, green: 0.608, blue: 0.941) : ThemeManager.secondaryText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .help(loc.t("reply"))
                
                // 2. Repost & Quote Menu
                // A plain Button that pops up an NSMenu on click: SwiftUI's Menu is backed by an NSPopUpButton,
                // and creating one per row as rows scroll into view was a major source of scroll hitches.
                HoverReader { hovered in
                    Button(action: showRepostMenu) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.system(size: 12, weight: tweet.isRetweeted ? .bold : .regular))
                            if tweet.retweetCount > 0 {
                                Text(formatCount(tweet.retweetCount))
                                    .font(.system(size: 12, weight: tweet.isRetweeted ? .semibold : .regular))
                            }
                        }
                        .foregroundColor(
                            tweet.isRetweeted || hovered ? Color(red: 0.0, green: 0.73, blue: 0.49) : ThemeManager.secondaryText
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .help(tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"))
                
                // 3. Like
                HoverReader { hovered in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.45, blendDuration: 0)) {
                            like.scale = 1.35
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                like.scale = 1.0
                            }
                        }
                        TimelineViewModel.shared.toggleLike(for: tweet)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tweet.isFavorited ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                                .scaleEffect(like.scale)
                            if tweet.favoriteCount > 0 {
                                Text(formatCount(tweet.favoriteCount))
                                    .font(.system(size: 12, weight: tweet.isFavorited ? .semibold : .regular))
                            }
                        }
                        .foregroundColor(
                            tweet.isFavorited || hovered ? Color(red: 0.976, green: 0.094, blue: 0.502) : ThemeManager.secondaryText
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .help(tweet.isFavorited ? loc.t("unlike") : loc.t("like"))
                
                // 4. Bookmark
                HoverReader { hovered in
                    Button(action: {
                        TimelineViewModel.shared.toggleBookmark(for: tweet)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tweet.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12))
                            if tweet.bookmarkCount > 0 {
                                Text(formatCount(tweet.bookmarkCount))
                                    .font(.system(size: 12, weight: tweet.isBookmarked ? .semibold : .regular))
                            }
                        }
                        .foregroundColor(
                            tweet.isBookmarked || hovered ? Color(red: 0.114, green: 0.608, blue: 0.941) : ThemeManager.secondaryText
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .help(tweet.isBookmarked ? loc.t("remove_bookmark") : loc.t("bookmark"))
            }
        }
    }
    
    private func showRepostMenu() {
        let menu = NSMenu()
        let tweet = tweet
        menu.addItem(ClosureMenuItem(
            title: tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"),
            symbol: "arrow.2.squarepath"
        ) {
            TimelineViewModel.shared.toggleRetweet(for: tweet)
        })
        menu.addItem(ClosureMenuItem(title: loc.t("quote_tweet"), symbol: "quote.bubble") {
            NavigationManager.shared.openComposer(quoting: tweet)
        })
        // Anchor at the click that triggered the button (screen coordinates), falling back to the cursor
        if let event = NSApp.currentEvent, let window = event.window,
           event.type == .leftMouseUp || event.type == .leftMouseDown {
            menu.popUp(positioning: nil, at: window.convertPoint(toScreen: event.locationInWindow), in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

// MARK: - Closure Menu Item
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    
    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func run() {
        handler()
    }
}
