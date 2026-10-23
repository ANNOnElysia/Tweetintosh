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
                    
                    // Tweet Body Text (Clean text with trailing media t.co URLs stripped)
                    if !tweet.cleanText.isEmpty {
                        Text(tweet.cleanText)
                            .font(theme.tweetFont(size: 14.5))
                            .lineSpacing(theme.lineSpacing())
                            .foregroundColor(ThemeManager.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    
                    // Media Photo / Video Grid
                    if !tweet.media.isEmpty {
                        ImageGridView(mediaList: tweet.media)
                            .padding(.top, 2)
                    }
                    
                    // Interaction Metrics Bar (Reply, Repost, Like, Share)
                    HStack(spacing: 36) {
                        // Reply
                        metricItem(icon: "bubble.left", count: tweet.replyCount)
                        
                        // Repost
                        metricItem(icon: "arrow.2.squarepath", count: tweet.retweetCount)
                        
                        // Like
                        metricItem(icon: "heart", count: tweet.favoriteCount)
                        
                        // Share
                        metricItem(icon: "bookmark", count: 0)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // 3. Subtle Row Divider
            Divider()
                .background(ThemeManager.border)
        }
        .background(Color.black)
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
