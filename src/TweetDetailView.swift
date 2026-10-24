//
//  TweetDetailView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

final class TweetDetailState: ObservableObject {
    @Published var isReplyingModal: Bool = false
    @Published var modalReplyTargetTweet: Tweet? = nil
    @Published var isHoveredBack: Bool = false
    @Published var isHoveredShare: Bool = false
    @Published var copiedLinkAlert: Bool = false
}

struct TweetDetailView: View {
    @StateObject var viewModel: TweetDetailViewModel
    var onDismiss: () -> Void
    
    @StateObject private var state = TweetDetailState()
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @FocusState private var isDockInputFocused: Bool
    
    init(tweet: Tweet, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: TweetDetailViewModel(focalTweet: tweet))
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()
            
            // Main Scrollable Thread Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Spacing for top floating Liquid Glass navigation header
                    Color.clear
                        .frame(height: 54)
                    
                    // 1. Ancestors (Parent tweets in the conversation thread)
                    if !viewModel.ancestors.isEmpty {
                        ForEach(Array(viewModel.ancestors.enumerated()), id: \.element.id) { index, ancestor in
                            ancestorTweetRow(ancestor, isLast: index == viewModel.ancestors.count - 1)
                        }
                    }
                    
                    // 2. Focal Hero Tweet Card
                    focalHeroTweetCard
                    
                    // Divider between focal tweet and replies
                    Rectangle()
                        .fill(ThemeManager.divider)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    
                    // 3. Replies Section Header
                    HStack {
                        Text(loc.t("thread_replies"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                        
                        Spacer()
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    
                    // 4. Replies List
                    if viewModel.replies.isEmpty {
                        if viewModel.isLoading {
                            // Loading skeleton shimmer
                            VStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    shimmerPlaceholderRow
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        } else {
                            // Empty replies notice
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 28))
                                    .foregroundColor(ThemeManager.secondaryText.opacity(0.6))
                                    .padding(.top, 24)
                                
                                Text(loc.t("no_replies_yet"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeManager.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 24)
                            }
                        }
                    } else {
                        ForEach(viewModel.replies, id: \.id) { reply in
                            replyTweetRow(reply)
                        }
                        
                        // Pagination trigger
                        if viewModel.bottomCursor != nil {
                            HStack {
                                Spacer()
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Color.clear
                                        .frame(height: 20)
                                        .onAppear {
                                            viewModel.loadMoreReplies()
                                        }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    
                    // Bottom padding to avoid overlapping the sticky reply dock
                    Color.clear
                        .frame(height: 72)
                }
            }
            
            // Top Floating Liquid Glass Navigation Bar
            topNavigationBar
            
            // Bottom Sticky Liquid Glass Reply Dock
            bottomReplyDock
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            viewModel.loadDetail()
        }
        .sheet(isPresented: $state.isReplyingModal) {
            if let target = state.modalReplyTargetTweet ?? Optional(viewModel.focalTweet) {
                ReplyComposerSheet(tweet: target)
            }
        }
    }
    
    // MARK: - Top Floating Liquid Glass Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Back Button
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text(loc.t("nav_back"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(ThemeManager.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(state.isHoveredBack ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)) : Color.clear)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { h in state.isHoveredBack = h }
            
            Spacer()
            
            Text(loc.t("nav_post"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            
            Spacer()
            
            // Copy Tweet Link Button
            Button(action: copyTweetLink) {
                Image(systemName: state.copiedLinkAlert ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(state.copiedLinkAlert ? Color(hex: "#00BA7C") : ThemeManager.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(state.isHoveredShare ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)) : Color.clear)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { h in state.isHoveredShare = h }
            .help(loc.t("copy_link"))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            ZStack {
                VisualEffectBackground(
                    material: theme.isLight ? .headerView : .hudWindow,
                    blendingMode: .withinWindow
                )
                (theme.isLight ? Color.white.opacity(0.8) : Color.black.opacity(0.4))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
    
    // MARK: - Focal Hero Tweet Card
    private var focalHeroTweetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info (Enlarged)
            HStack(spacing: 12) {
                avatarView(url: viewModel.focalTweet.author.avatarUrl, size: 44)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(viewModel.focalTweet.author.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                        
                        if viewModel.focalTweet.author.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    
                    Text(viewModel.focalTweet.author.formattedHandle)
                        .font(.system(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                }
                
                Spacer()
            }
            
            // Tweet Body Text (Large, crisp typography)
            if !viewModel.focalTweet.cleanText.isEmpty {
                Text(viewModel.focalTweet.cleanText)
                    .font(theme.tweetFont(size: 17))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            
            // Media Grid (Images / Video)
            if !viewModel.focalTweet.media.isEmpty {
                ImageGridView(mediaList: viewModel.focalTweet.media, tweet: viewModel.focalTweet)
                    .padding(.top, 4)
            }
            
            // Embedded Quoted Tweet (if any)
            if let quoted = viewModel.focalTweet.quoted {
                QuotedTweetCard(tweet: quoted)
                    .padding(.top, 6)
            }
            
            // Formatted Date & Time
            HStack(spacing: 6) {
                Text(formattedExactDate(viewModel.focalTweet.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
            }
            .padding(.top, 4)
            
            // Metrics Counter Bar (Reposts, Likes, Bookmarks)
            if viewModel.focalTweet.retweetCount > 0 || viewModel.focalTweet.favoriteCount > 0 || viewModel.focalTweet.bookmarkCount > 0 {
                Divider()
                    .background(ThemeManager.divider)
                
                HStack(spacing: 16) {
                    if viewModel.focalTweet.retweetCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.retweetCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("retweet"))
                                .font(.system(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    if viewModel.focalTweet.favoriteCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.favoriteCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("like"))
                                .font(.system(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    if viewModel.focalTweet.bookmarkCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.bookmarkCount)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("bookmark"))
                                .font(.system(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            
            Divider()
                .background(ThemeManager.divider)
            
            // Interactive Social Action Bar
            heroActionBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Hero Tweet Action Bar
    private var heroActionBar: some View {
        HStack {
            // Reply Button
            actionButton(
                icon: "bubble.left",
                activeIcon: "bubble.left.fill",
                count: viewModel.focalTweet.replyCount,
                isActive: false,
                activeColor: ThemeManager.accent
            ) {
                state.modalReplyTargetTweet = viewModel.focalTweet
                state.isReplyingModal = true
            }
            
            Spacer()
            
            // Retweet & Quote Menu
            Menu {
                Button(action: {
                    viewModel.toggleRetweet(for: viewModel.focalTweet)
                }) {
                    Label(viewModel.focalTweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"), systemImage: "arrow.2.squarepath")
                }
                Button(action: {
                    NavigationManager.shared.openComposer(quoting: viewModel.focalTweet)
                }) {
                    Label(loc.t("quote_tweet"), systemImage: "quote.bubble")
                }
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 18))
                    .foregroundColor(viewModel.focalTweet.isRetweeted ? Color(hex: "#00BA7C") : ThemeManager.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(viewModel.focalTweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"))
            
            Spacer()
            
            // Like Button
            actionButton(
                icon: "heart",
                activeIcon: "heart.fill",
                count: viewModel.focalTweet.favoriteCount,
                isActive: viewModel.focalTweet.isFavorited,
                activeColor: Color(hex: "#F91880")
            ) {
                viewModel.toggleLike(for: viewModel.focalTweet)
            }
            
            Spacer()
            
            // Bookmark Button
            actionButton(
                icon: "bookmark",
                activeIcon: "bookmark.fill",
                count: viewModel.focalTweet.bookmarkCount,
                isActive: viewModel.focalTweet.isBookmarked,
                activeColor: ThemeManager.accent
            ) {
                viewModel.toggleBookmark(for: viewModel.focalTweet)
            }
            
            Spacer()
            
            // Share Button
            Button(action: copyTweetLink) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                    .foregroundColor(ThemeManager.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Ancestor Tweet Row (With Thread Line)
    private var ancestorLineColor: Color {
        ThemeManager.divider.opacity(0.8)
    }
    
    @ViewBuilder
    private func ancestorTweetRow(_ tweet: Tweet, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: Avatar + Vertical Thread Line
            VStack(spacing: 0) {
                avatarView(url: tweet.author.avatarUrl, size: 36)
                
                // Connecting line
                Rectangle()
                    .fill(ancestorLineColor)
                    .frame(width: 2)
                    .frame(minHeight: 24)
            }
            .padding(.leading, 16)
            
            // Right column: Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(tweet.author.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                    
                    if tweet.author.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeManager.accent)
                    }
                    
                    Text(tweet.author.formattedHandle)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                    
                    Spacer()
                }
                
                Text(tweet.text)
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineSpacing(3)
                
                if !tweet.media.isEmpty {
                    ImageGridView(mediaList: tweet.media, tweet: tweet)
                        .padding(.top, 2)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
    }
    
    // MARK: - Reply Tweet Row
    @ViewBuilder
    private func replyTweetRow(_ tweet: Tweet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                avatarView(url: tweet.author.avatarUrl, size: 36)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Author Header
                    HStack(spacing: 4) {
                        Text(tweet.author.name)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                        
                        if tweet.author.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11.5))
                                .foregroundColor(ThemeManager.accent)
                        }
                        
                        Text(tweet.author.formattedHandle)
                            .font(.system(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                        
                        Spacer()
                    }
                    
                    // Reply Text
                    if !tweet.text.isEmpty {
                        Text(tweet.text)
                            .font(.system(size: 13.5))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                    
                    // Media
                    if !tweet.media.isEmpty {
                        ImageGridView(mediaList: tweet.media, tweet: tweet)
                            .padding(.top, 4)
                    }
                    
                    // Embedded Quoted Tweet (if any)
                    if let quoted = tweet.quoted {
                        QuotedTweetCard(tweet: quoted)
                            .padding(.top, 4)
                    }
                    
                    // Reply Action Bar (Compact)
                    HStack(spacing: 24) {
                        // Reply to this reply
                        Button(action: {
                            state.modalReplyTargetTweet = tweet
                            state.isReplyingModal = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 12))
                                if tweet.replyCount > 0 {
                                    Text("\(tweet.replyCount)")
                                        .font(.system(size: 11))
                                }
                            }
                            .foregroundColor(ThemeManager.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Retweet & Quote Menu
                        Menu {
                            Button(action: {
                                viewModel.toggleRetweet(for: tweet)
                            }) {
                                Label(tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"), systemImage: "arrow.2.squarepath")
                            }
                            Button(action: {
                                NavigationManager.shared.openComposer(quoting: tweet)
                            }) {
                                Label(loc.t("quote_tweet"), systemImage: "quote.bubble")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.system(size: 12))
                                if tweet.retweetCount > 0 {
                                    Text("\(tweet.retweetCount)")
                                        .font(.system(size: 11))
                                }
                            }
                            .foregroundColor(tweet.isRetweeted ? Color(hex: "#00BA7C") : ThemeManager.secondaryText)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        
                        // Like
                        Button(action: {
                            viewModel.toggleLike(for: tweet)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: tweet.isFavorited ? "heart.fill" : "heart")
                                    .font(.system(size: 12))
                                if tweet.favoriteCount > 0 {
                                    Text("\(tweet.favoriteCount)")
                                        .font(.system(size: 11))
                                }
                            }
                            .foregroundColor(tweet.isFavorited ? Color(hex: "#F91880") : ThemeManager.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Bookmark
                        Button(action: {
                            viewModel.toggleBookmark(for: tweet)
                        }) {
                            Image(systemName: tweet.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12))
                                .foregroundColor(tweet.isBookmarked ? ThemeManager.accent : ThemeManager.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Rectangle()
                .fill(ThemeManager.divider.opacity(0.6))
                .frame(height: 0.5)
                .padding(.leading, 62)
        }
    }
    
    // MARK: - Bottom Sticky Liquid Glass Reply Dock
    private var bottomReplyDock: some View {
        HStack(spacing: 10) {
            // User Avatar Placeholder
            Circle()
                .fill(ThemeManager.cardBackground)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(ThemeManager.secondaryText)
                )
            
            // Text Input Field
            TextField(loc.t("reply_placeholder"), text: $viewModel.quickReplyText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .foregroundColor(ThemeManager.primaryText)
                .focused($isDockInputFocused)
                .onSubmit {
                    viewModel.postQuickReply()
                }
            
            // Submit Button
            if !viewModel.quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: {
                    viewModel.postQuickReply()
                }) {
                    if viewModel.isSubmittingReply {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 26, height: 26)
                    } else {
                        Text(loc.t("post_reply"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(ThemeManager.accent)
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            ZStack {
                VisualEffectBackground(
                    material: theme.isLight ? .headerView : .hudWindow,
                    blendingMode: .withinWindow
                )
                (theme.isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Reusable Action Button
    @ViewBuilder
    private func actionButton(
        icon: String,
        activeIcon: String,
        count: Int,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: 15))
                    .foregroundColor(isActive ? activeColor : ThemeManager.secondaryText)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isActive ? activeColor : ThemeManager.secondaryText)
                }
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Avatar View
    @ViewBuilder
    private func avatarView(url: String?, size: CGFloat) -> some View {
        CachedAsyncImage(urlString: url)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
    }
    
    // MARK: - Shimmer Placeholder Row
    private var shimmerPlaceholderRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ThemeManager.cardBackground)
                .frame(width: 34, height: 34)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ThemeManager.cardBackground)
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ThemeManager.cardBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ThemeManager.cardBackground)
                    .frame(width: 180, height: 12)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    private func formattedExactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: loc.currentLanguage.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func copyTweetLink() {
        let url = "https://x.com/\(viewModel.focalTweet.author.screenName)/status/\(viewModel.focalTweet.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        
        withAnimation {
            state.copiedLinkAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                self.state.copiedLinkAlert = false
            }
        }
    }
}
