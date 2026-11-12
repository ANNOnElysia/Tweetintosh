//
//  QuotedTweetCard.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

// Which post is hovered rather than a flag, so a reused table cell doesn't carry the highlight to its next post
final class QuotedCardState: ObservableObject {
    @Published var hoveredId: String?
}

struct QuotedTweetCard: View {
    @Environment(\.isInDetailPane) private var isInDetailPane
    let tweet: Tweet
    var isInteractive: Bool = true
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var state = QuotedCardState()
    
    private var isHovered: Bool { state.hoveredId == tweet.id }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Author Header
            HStack(spacing: 6) {
                if let avatarUrl = tweet.author.avatarUrl {
                    CachedAsyncImage(urlString: avatarUrl, targetSize: CGSize(width: 20, height: 20))
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ThemeManager.border.opacity(0.6), lineWidth: 0.5))
                        .peekable(.profile(tweet.author))
                        .opensProfile(tweet.author)
                } else {
                    Circle()
                        .fill(ThemeManager.secondaryText.opacity(0.2))
                        .frame(width: 20, height: 20)
                }
                
                // One hit target for the whole name, as on the post itself
                HStack(spacing: 6) {
                    Text(tweet.author.name)
                        .font(theme.appFont(size: 13, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    
                    Text(tweet.author.formattedHandle)
                        .font(theme.appFont(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                }
                .peekable(.profile(tweet.author))
                .opensProfile(tweet.author)
                
                Text("·")
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Text(tweet.relativeTime)
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Spacer()
            }
            
            // 2. Tweet Text Content
            if let replyContext = tweet.replyContextText {
                Text(replyContext)
                    .font(theme.appFont(size: 11.5))
                    .foregroundColor(ThemeManager.secondaryText)
                    .lineLimit(1)
            }
            
            if !tweet.displayBodyText.isEmpty {
                TweetText.text(tweet)
                    .handlesTweetLinks()
                    .font(theme.tweetFont(size: theme.postSize(13)))
                    .lineSpacing(theme.lineSpacing() * 0.8)
                    .foregroundColor(ThemeManager.primaryText.opacity(0.92))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .peeksText(of: tweet, fontSize: theme.postSize(13), lineSpacing: theme.lineSpacing() * 0.8)
            }
            
            // 3. Media Preview (reusing ImageGridView with isQuoted scaling)
            if !tweet.media.isEmpty {
                ImageGridView(mediaList: tweet.media, tweet: tweet, isInteractive: isInteractive, isQuoted: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.isLight ? Color.black.opacity(isHovered ? 0.04 : 0.02) : Color.white.opacity(isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered ? ThemeManager.accent.opacity(0.4) : ThemeManager.border.opacity(0.7), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .navigationPointer(isInteractive)
        .allowsHitTesting(isInteractive)
        .onHover { hovering in
            if isInteractive {
                state.hoveredId = hovering ? tweet.id : nil
            }
        }
        .onTapGesture {
            if isInteractive {
                NavigationManager.shared.openTweetDetail(tweet, fromPane: isInDetailPane)
            }
        }
    }
}
