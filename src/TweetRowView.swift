//
//  TweetRowView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI

final class TweetRowState: ObservableObject {
    @Published var isShowingReplySheet: Bool = false
    @Published var isReplyHovered: Bool = false
    @Published var isRepostHovered: Bool = false
    @Published var isLikeHovered: Bool = false
    @Published var isBookmarkHovered: Bool = false
    @Published var likeScale: CGFloat = 1.0
}

struct TweetRowView: View {
    let tweet: Tweet
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @StateObject private var state = TweetRowState()
    
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
                    CachedAsyncImage(urlString: tweet.author.avatarUrl)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                    
                    // Content Column
                    VStack(alignment: .leading, spacing: 6) {
                        // Header: Author Name, Verified Badge, Handle, Dot, Relative Time
                        HStack(alignment: .center, spacing: 4) {
                            Text(tweet.author.name)
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                                .lineLimit(1)
                            
                            if tweet.author.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeManager.accent)
                            }
                            
                            Text(tweet.author.formattedHandle)
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                                .lineLimit(1)
                            
                            Text("·")
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                            
                            Text(tweet.relativeTime)
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                            
                            Spacer()
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
                            Text(tweet.displayBodyText)
                                .font(theme.tweetFont(size: 14.5))
                                .lineSpacing(theme.lineSpacing())
                                .foregroundColor(ThemeManager.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
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
            
            // 3. Interaction Metrics Bar (Reply, Repost, Like, Bookmark)
            // Kept outside content onTapGesture to allow direct, uninhibited interaction with buttons & menus
            HStack(spacing: 32) {
                // 1. Reply
                Button(action: { state.isShowingReplySheet = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 12))
                        if tweet.replyCount > 0 {
                            Text(formatCount(tweet.replyCount))
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(state.isReplyHovered ? Color(red: 0.114, green: 0.608, blue: 0.941) : ThemeManager.secondaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { state.isReplyHovered = $0 }
                .help(loc.t("reply"))
                
                // 2. Repost & Quote Menu
                Menu {
                    Button(action: {
                        TimelineViewModel.shared.toggleRetweet(for: tweet)
                    }) {
                        Label(tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"), systemImage: "arrow.2.squarepath")
                    }
                    Button(action: {
                        NavigationManager.shared.openComposer(quoting: tweet)
                    }) {
                        Label(loc.t("quote_tweet"), systemImage: "quote.bubble")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 12, weight: tweet.isRetweeted ? .bold : .regular))
                        if tweet.retweetCount > 0 {
                            Text(formatCount(tweet.retweetCount))
                                .font(.system(size: 12, weight: tweet.isRetweeted ? .semibold : .regular))
                        }
                    }
                    .foregroundColor(
                        tweet.isRetweeted ? Color(red: 0.0, green: 0.73, blue: 0.49) :
                        (state.isRepostHovered ? Color(red: 0.0, green: 0.73, blue: 0.49) : ThemeManager.secondaryText)
                    )
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .onHover { state.isRepostHovered = $0 }
                .help(tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"))
                
                // 3. Like
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45, blendDuration: 0)) {
                        state.likeScale = 1.35
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            state.likeScale = 1.0
                        }
                    }
                    TimelineViewModel.shared.toggleLike(for: tweet)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: tweet.isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .scaleEffect(state.likeScale)
                        if tweet.favoriteCount > 0 {
                            Text(formatCount(tweet.favoriteCount))
                                .font(.system(size: 12, weight: tweet.isFavorited ? .semibold : .regular))
                        }
                    }
                    .foregroundColor(
                        tweet.isFavorited ? Color(red: 0.976, green: 0.094, blue: 0.502) :
                        (state.isLikeHovered ? Color(red: 0.976, green: 0.094, blue: 0.502) : ThemeManager.secondaryText)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { state.isLikeHovered = $0 }
                .help(tweet.isFavorited ? loc.t("unlike") : loc.t("like"))
                
                // 4. Bookmark
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
                        tweet.isBookmarked ? Color(red: 0.114, green: 0.608, blue: 0.941) :
                        (state.isBookmarkHovered ? Color(red: 0.114, green: 0.608, blue: 0.941) : ThemeManager.secondaryText)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { state.isBookmarkHovered = $0 }
                .help(tweet.isBookmarked ? loc.t("remove_bookmark") : loc.t("bookmark"))
                
                Spacer()
            }
            .padding(.leading, 66) // Aligns with text column (16 horizontal padding + 40 avatar + 10 spacing)
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            // 4. Subtle Row Divider
            Divider()
                .background(ThemeManager.divider)
        }
        .background(ThemeManager.background)
        .sheet(isPresented: $state.isShowingReplySheet) {
            ReplyComposerSheet(tweet: tweet)
        }
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
    
    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
    
    private func openTweetOnWeb() {
        let urlStr = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}
