//
//  QuotedTweetCard.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

final class QuotedCardState: ObservableObject {
    @Published var isHovered: Bool = false
}

struct QuotedTweetCard: View {
    let tweet: Tweet
    var isInteractive: Bool = true
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var state = QuotedCardState()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Author Header
            HStack(spacing: 6) {
                if let avatarUrl = tweet.author.avatarUrl {
                    CachedAsyncImage(urlString: avatarUrl)
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ThemeManager.border.opacity(0.6), lineWidth: 0.5))
                        .opensProfile(tweet.author)
                } else {
                    Circle()
                        .fill(ThemeManager.secondaryText.opacity(0.2))
                        .frame(width: 20, height: 20)
                }
                
                Text(tweet.author.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
                    .opensProfile(tweet.author)
                
                Text(tweet.author.formattedHandle)
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                    .lineLimit(1)
                
                Text("·")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Text(tweet.relativeTime)
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Spacer()
            }
            
            // 2. Tweet Text Content
            if let replyContext = tweet.replyContextText {
                Text(replyContext)
                    .font(.system(size: 11.5))
                    .foregroundColor(ThemeManager.secondaryText)
                    .lineLimit(1)
            }
            
            if !tweet.displayBodyText.isEmpty {
                Text(TweetText.attributed(tweet))
                    .handlesTweetLinks()
                    .font(theme.tweetFont(size: 13))
                    .lineSpacing(theme.lineSpacing() * 0.8)
                    .foregroundColor(ThemeManager.primaryText.opacity(0.92))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 3. Media Preview (reusing ImageGridView with isQuoted scaling)
            if !tweet.media.isEmpty {
                ImageGridView(mediaList: tweet.media, tweet: tweet, isInteractive: isInteractive, isQuoted: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.isLight ? Color.black.opacity(state.isHovered ? 0.04 : 0.02) : Color.white.opacity(state.isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(state.isHovered ? ThemeManager.accent.opacity(0.4) : ThemeManager.border.opacity(0.7), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            if isInteractive {
                state.isHovered = hovering
            }
        }
        .onTapGesture {
            if isInteractive {
                NavigationManager.shared.openTweetDetail(tweet)
            }
        }
    }
}
