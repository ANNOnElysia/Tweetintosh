//
//  TweetDetailView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

// Pull-down to refresh for the post page, owned by the page itself (the timeline's coordinator is a single shared
// object tied to the page underneath). Works like the timeline's: a pull past the threshold that starts to spring
// back refreshes.
final class DetailPullController: ObservableObject {
    @Published var pullDistance: CGFloat = 0
    var onTrigger: (() -> Void)?
    var isBusy = false

    private weak var scrollView: NSScrollView?
    private var observer: Any?
    private var peak: CGFloat = 0
    private var triggered = false
    private var hapticSent = false
    private let threshold = TrackpadPullCoordinator.refreshThreshold

    func attach(_ sv: NSScrollView) {
        guard scrollView !== sv else { return }
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = sv
        sv.verticalScrollElasticity = .allowed
        sv.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main) { [weak self] _ in
            self?.boundsChanged()
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func boundsChanged() {
        guard let sv = scrollView, !isBusy else { return }
        let overscroll = sv.restingTopY - sv.contentView.bounds.origin.y
        if overscroll > 0.5 {
            pullDistance = overscroll
            peak = max(peak, overscroll)
            if overscroll >= threshold && !hapticSent {
                hapticSent = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if !triggered && peak >= threshold && overscroll <= peak - 6 {
                triggered = true
                pullDistance = 0
                onTrigger?()
            }
        } else {
            peak = 0
            triggered = false
            hapticSent = false
            if pullDistance != 0 { pullDistance = 0 }
        }
    }
}

// The spinner that follows a pull and stays while the page refreshes
private struct DetailPullIndicator: View {
    @ObservedObject var pull: DetailPullController
    @ObservedObject var viewModel: TweetDetailViewModel
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if viewModel.isRefreshing || pull.pullDistance > 2 {
            let distance = viewModel.isRefreshing ? 40.0 : pull.pullDistance
            let progress = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, distance / TrackpadPullCoordinator.refreshThreshold))
            SVGRefreshIndicatorView(pullProgress: progress, isRefreshing: viewModel.isRefreshing, colorScheme: theme.themeColor)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .offset(y: 62 + (distance - 40.0) / 2.0)
                .opacity(viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(distance - 2.0) / 8.0)))
                .allowsHitTesting(false)
        }
    }
}

final class TweetDetailState: ObservableObject {
    // Not published: the page must not redraw on every pull, only the spinner does
    let pull = DetailPullController()
    @Published var isReplyingModal: Bool = false
    @Published var modalReplyTargetTweet: Tweet? = nil
    @Published var isHoveredBack: Bool = false
    @Published var isHoveredShare: Bool = false
    @Published var copiedLinkAlert: Bool = false
    // Conversations (by their first reply) that have been opened past the first few replies
    @Published var expandedThreads: Set<String> = []
    // Conversations whose further replies are being fetched
    @Published var loadingThreads: Set<String> = []
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
            // Spacing for top floating Liquid Glass navigation header
            ScrollContainer(topSpacer: 54 + (viewModel.isRefreshing ? 40 : 0), onScrollView: { state.pull.attach($0) }, onNearBottom: { viewModel.loadMoreReplies() }) {
                    
                    // 1. Ancestors (Parent tweets in the conversation thread)
                    if !viewModel.ancestors.isEmpty {
                        ForEach(Array(viewModel.ancestors.enumerated()), id: \.element.id) { index, ancestor in
                            ancestorTweetRow(ancestor, isLast: index == viewModel.ancestors.count - 1)
                        }
                    }
                    
                    // 2. Focal Hero Tweet Card
                    focalHeroTweetCard
                    
                    // 3. Replies Section Header, with the divider between focal tweet and replies above it
                    // (one row: a 1pt divider on its own would be padded to a full row height in a List)
                    VStack(spacing: 0) {
                    Rectangle()
                        .fill(ThemeManager.divider)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    
                    HStack {
                        Text(loc.t("thread_replies"))
                            .font(theme.appFont(size: 15, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                        
                        Spacer()
                        
                        if viewModel.isLoading {
                            LoadingIndicator(compactHeight: 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    }
                    
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
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 28))
                                        .foregroundColor(ThemeManager.secondaryText.opacity(0.6))
                                        .padding(.top, 32)
                                    
                                    Text(loc.t("no_replies_yet"))
                                        .font(theme.appFont(size: 13, weight: .medium))
                                        .foregroundColor(ThemeManager.secondaryText)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                        .padding(.bottom, 32)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        // Each conversation is one list row: its replies run straight down, joined by a line
                        ForEach(viewModel.replyThreads, id: \.first!.id) { thread in
                            replyThreadView(thread)
                        }
                        
                        // Pagination trigger
                        if viewModel.bottomCursor != nil {
                            Group {
                                if viewModel.isLoadingMore {
                                    LoadingIndicator()
                                } else {
                                    Color.clear
                                        .frame(height: 20)
                                        .onAppear {
                                            viewModel.loadMoreReplies()
                                        }
                                }
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    
                    // Bottom padding to avoid overlapping the sticky reply dock
                    Color.clear
                        .frame(height: 72)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isRefreshing)
            
            DetailPullIndicator(pull: state.pull, viewModel: viewModel)
            
            // Top Floating Liquid Glass Navigation Bar
            topNavigationBar
            
            // Bottom Sticky Liquid Glass Reply Dock
            bottomReplyDock
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            viewModel.loadDetail()
            state.pull.onTrigger = { [weak viewModel] in viewModel?.refresh() }
        }
        .onChange(of: viewModel.isRefreshing) {
            state.pull.isBusy = viewModel.isRefreshing
        }
        // Command+R refreshes the page in front, like it does the timeline
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_RefreshTimeline"))) { _ in
            if case .tweet(let page)? = NavigationManager.shared.overlayStack.last?.page, page.id == viewModel.focalTweet.id {
                viewModel.refresh()
            }
        }
        .sheet(isPresented: $state.isReplyingModal) {
            if let target = state.modalReplyTargetTweet ?? Optional(viewModel.focalTweet) {
                ReplyComposerSheet(tweet: target)
            }
        }
    }
    
    // MARK: - Top Floating Navigation Bar (Dual-Mode: Liquid Glass vs Classic Frosted Glass)
    @ViewBuilder
    private var topNavigationBar: some View {
        if theme.useLiquidGlass {
            liquidGlassTopNavigation
        } else {
            frostedGlassTopNavigationBar
        }
    }
    
    // Mode A: Native Liquid Glass Navigation Controls (Strict Apple Glass HIG: Standalone circular droplets with ONLY chevron arrow)
    private var liquidGlassTopNavigation: some View {
        HStack {
            // Liquid Glass Back Button (Only left arrow icon, standalone circular glass droplet)
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Group {
                            if #available(macOS 26.0, *) {
                                let glassStyle: Glass = theme.useLiquidGlassTint
                                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.18)).interactive()
                                    : .regular.interactive()
                                Circle()
                                    .fill(theme.isLight ? Color.white.opacity(0.68) : Color.black.opacity(0.24))
                                    .tweetGlass(glassStyle, in: Circle())
                            } else {
                                Circle()
                                    .fill(theme.isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.45))
                            }
                        }
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                theme.isLight ? Color(hex: "#DED9CB").opacity(0.85) : Color.white.opacity(0.22),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.35), radius: 10, x: 0, y: 3)
                    .scaleEffect(state.isHoveredBack ? 1.05 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { h in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    state.isHoveredBack = h
                }
            }
            .help("\(loc.t("nav_back")) (Esc / ←)")
            
            Spacer()
            
            // Liquid Glass Share / Copy Link Button (standalone circular glass droplet)
            Button(action: copyTweetLink) {
                Image(systemName: state.copiedLinkAlert ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(state.copiedLinkAlert ? Color(hex: "#00BA7C") : ThemeManager.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Group {
                            if #available(macOS 26.0, *) {
                                let glassStyle: Glass = theme.useLiquidGlassTint
                                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.18)).interactive()
                                    : .regular.interactive()
                                Circle()
                                    .fill(theme.isLight ? Color.white.opacity(0.68) : Color.black.opacity(0.24))
                                    .tweetGlass(glassStyle, in: Circle())
                            } else {
                                Circle()
                                    .fill(theme.isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.45))
                            }
                        }
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                theme.isLight ? Color(hex: "#DED9CB").opacity(0.85) : Color.white.opacity(0.22),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.35), radius: 10, x: 0, y: 3)
                    .scaleEffect(state.isHoveredShare ? 1.05 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { h in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    state.isHoveredShare = h
                }
            }
            .help(loc.t("copy_link"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
    
    // Mode B: Classic Frosted Glass Navigation Bar (Gaussian Blur when Liquid Glass is off)
    private var frostedGlassTopNavigationBar: some View {
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
            .help("\(loc.t("nav_back")) (Esc / ←)")
            
            Spacer()
            
            Text(loc.t("nav_post"))
                .font(theme.appFont(size: 14, weight: .bold))
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
                    .peekable(.profile(viewModel.focalTweet.author))
                    .opensProfile(viewModel.focalTweet.author)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(viewModel.focalTweet.author.name)
                            .font(theme.appFont(size: 15, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                            .peekable(.profile(viewModel.focalTweet.author))
                            .opensProfile(viewModel.focalTweet.author)
                        
                        if viewModel.focalTweet.author.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    
                    Text(viewModel.focalTweet.author.formattedHandle)
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                        .peekable(.profile(viewModel.focalTweet.author))
                        .opensProfile(viewModel.focalTweet.author)
                }
                
                Spacer()
                
                if viewModel.focalTweet.isPromoted {
                    AdBadgeView()
                }
                
                TweetOptionsMenuButton(tweet: viewModel.focalTweet, onToggleBookmark: {
                    viewModel.toggleBookmark(for: viewModel.focalTweet)
                })
            }
            
            // Reply Context Subheader (Consistent with official X logic)
            if let replyContext = viewModel.focalTweet.replyContextText {
                Text(replyContext)
                    .font(theme.appFont(size: 13))
                    .foregroundColor(ThemeManager.secondaryText)
                    .lineLimit(1)
            }
            
            // Tweet Body Text (Large, crisp typography)
            if !viewModel.focalTweet.displayBodyText.isEmpty {
                Text(TweetText.attributed(viewModel.focalTweet))
                    .handlesTweetLinks()
                    .font(theme.tweetFont(size: 17))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            
            // An X Article attached to the post: opens the reader
            if viewModel.focalTweet.linksToArticle {
                TweetArticleCard(tweet: viewModel.focalTweet)
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
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.secondaryText)
            }
            .padding(.top, 4)
            
            // Metrics Counter Bar (Views, Reposts, Likes, Bookmarks)
            if viewModel.focalTweet.retweetCount > 0 || viewModel.focalTweet.favoriteCount > 0 || viewModel.focalTweet.bookmarkCount > 0 || (viewModel.focalTweet.viewCount ?? 0) > 0 {
                Divider()
                    .background(ThemeManager.divider)
                
                HStack(spacing: 16) {
                    if let views = viewModel.focalTweet.viewCount, views > 0 {
                        HStack(spacing: 4) {
                            Text(formatCount(views))
                                .font(theme.appFont(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("views"))
                                .font(theme.appFont(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    if viewModel.focalTweet.retweetCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.retweetCount)")
                                .font(theme.appFont(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("retweet"))
                                .font(theme.appFont(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    if viewModel.focalTweet.favoriteCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.favoriteCount)")
                                .font(theme.appFont(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("like"))
                                .font(theme.appFont(size: 13))
                                .foregroundColor(ThemeManager.secondaryText)
                        }
                    }
                    if viewModel.focalTweet.bookmarkCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(viewModel.focalTweet.bookmarkCount)")
                                .font(theme.appFont(size: 13, weight: .bold))
                                .foregroundColor(ThemeManager.primaryText)
                            Text(loc.t("bookmark"))
                                .font(theme.appFont(size: 13))
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
                guard EngagementGuard.allows(viewModel.focalTweet) else { return }
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
                    .peekable(.profile(tweet.author))
                    .opensProfile(tweet.author)
                
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
                        .font(theme.appFont(size: 13.5, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .peekable(.profile(tweet.author))
                        .opensProfile(tweet.author)
                    
                    if tweet.author.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeManager.accent)
                    }
                    
                    Text(tweet.author.formattedHandle)
                        .font(theme.appFont(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                        .peekable(.profile(tweet.author))
                        .opensProfile(tweet.author)
                    
                    Spacer()
                    
                    if tweet.isPromoted {
                        AdBadgeView()
                    }
                    
                    TweetOptionsMenuButton(tweet: tweet, onToggleBookmark: {
                        viewModel.toggleBookmark(for: tweet)
                    })
                }
                
                if let replyContext = tweet.replyContextText {
                    Text(replyContext)
                        .font(theme.appFont(size: 12))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                }
                
                if !tweet.displayBodyText.isEmpty {
                    Text(TweetText.attributed(tweet))
                        .handlesTweetLinks()
                        .font(theme.appFont(size: 13.5))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineSpacing(theme.lineSpacing() * 0.7)
                }
                
                if !tweet.media.isEmpty {
                    ImageGridView(mediaList: tweet.media, tweet: tweet)
                        .padding(.top, 2)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
    }
    
    // MARK: - Reply Conversation
    // Like the official app: under each reply, only the post author's answer to it is shown. Anything further
    // down the conversation sits behind "Show replies", which expands inline when it is a single chain and opens
    // the reply's own page when it branches.
    @ViewBuilder
    private func replyThreadView(_ thread: [Tweet]) -> some View {
        let root = thread[0]
        let authorId = viewModel.focalTweet.author.id
        let authorAnswer = thread.dropFirst().first { $0.inReplyToStatusId == root.id && $0.author.id == authorId }
        let expanded = state.expandedThreads.contains(root.id)
        let shown: [Tweet] = expanded ? thread : (authorAnswer.map { [root, $0] } ?? [root])
        // What "Show replies" would reveal: only offered under the author's answer
        let tail = authorAnswer ?? root
        let hasMore: Bool = {
            guard !expanded, let answer = authorAnswer else { return false }
            return answer.replyCount > 0 || root.replyCount > 1 || thread.count > 2
        }()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, reply in
                let isLast = index == shown.count - 1
                replyTweetRow(reply, linkAbove: index > 0, linkBelow: isLast ? hasMore : true)
            }
            if hasMore {
                showRepliesRow {
                    // One reply beneath each (and loaded): open it here. More than one, or not loaded: its own page.
                    // On a reply's own page there is no further page to go to, so it always opens in place.
                    let onReplyPage = viewModel.focalTweet.inReplyToStatusId != nil
                    let opensInPlace = onReplyPage || (root.replyCount <= 1 && tail.replyCount <= 1)
                    guard opensInPlace else {
                        NavigationManager.shared.openTweetDetail(root.replyCount > 1 ? root : tail)
                        return
                    }
                    let expand = {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            _ = state.expandedThreads.insert(root.id)
                            _ = state.loadingThreads.remove(root.id)
                        }
                    }
                    if thread.count > shown.count {
                        expand()
                    } else if !state.loadingThreads.contains(root.id) {
                        // X didn't send these replies: fetch the ones under the author's answer, then show them
                        state.loadingThreads.insert(root.id)
                        viewModel.loadSubReplies(of: tail, completion: expand)
                    }
                }
            }
        }
    }
    
    // The line from the reply above ends in three dots, then the link
    private func showRepliesRow(action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(ThemeManager.secondaryText.opacity(0.45))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(width: 36)
                .padding(.leading, 16)
                Button(action: action) {
                    Text(loc.t("show_replies"))
                        .font(theme.appFont(size: 13.5))
                        .foregroundColor(ThemeManager.accent)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Rectangle()
                .fill(ThemeManager.divider.opacity(0.6))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Reply Tweet Row
    @ViewBuilder
    private func replyTweetRow(_ tweet: Tweet, depth: Int = 0, linkAbove: Bool = false, linkBelow: Bool = false, parentDepth: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                avatarView(url: tweet.author.avatarUrl, size: 36)
                    .peekable(.profile(tweet.author))
                    .opensProfile(tweet.author)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Author Header
                    HStack(spacing: 4) {
                        Text(tweet.author.name)
                            .font(theme.appFont(size: 13.5, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                            .peekable(.profile(tweet.author))
                            .opensProfile(tweet.author)
                        
                        if tweet.author.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11.5))
                                .foregroundColor(ThemeManager.accent)
                        }
                        
                        Text(tweet.author.formattedHandle)
                            .font(theme.appFont(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                            .peekable(.profile(tweet.author))
                            .opensProfile(tweet.author)
                        
                        Spacer()
                        
                        if tweet.isPromoted {
                            AdBadgeView()
                        }
                        
                        TweetOptionsMenuButton(tweet: tweet, onToggleBookmark: {
                            viewModel.toggleBookmark(for: tweet)
                        })
                    }
                    
                    // Reply Context Subheader (Consistent with official X logic)
                    if let replyContext = tweet.replyContextText {
                        Text(replyContext)
                            .font(theme.appFont(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                            .lineLimit(1)
                    }
                    
                    // Reply Text (Clean text with leading reply mentions & trailing media URLs stripped)
                    if !tweet.displayBodyText.isEmpty {
                        Text(TweetText.attributed(tweet))
                            .handlesTweetLinks()
                            .font(theme.appFont(size: 13.5))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineSpacing(theme.lineSpacing() * 0.7)
                            .textSelection(.enabled)
                    }
                    
                    // Media
                    if !tweet.media.isEmpty {
                        ImageGridView(mediaList: tweet.media, tweet: tweet, isQuoted: true)
                            .padding(.top, 4)
                    }
                    
                    // Embedded Quoted Tweet (if any)
                    if let quoted = tweet.quoted {
                        QuotedTweetCard(tweet: quoted)
                            .padding(.top, 4)
                    }
                    
                    // Reply Action Bar (Compact)
                    HStack(alignment: .center) {
                        // Left: Reply to this reply
                        Button(action: {
                            guard EngagementGuard.allows(tweet) else { return }
                            state.modalReplyTargetTweet = tweet
                            state.isReplyingModal = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 12))
                                if tweet.replyCount > 0 {
                                    Text("\(tweet.replyCount)")
                                        .font(theme.appFont(size: 11))
                                }
                            }
                            .foregroundColor(ThemeManager.secondaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        // Right group: Like + Retweet (转帖塞在右边)
                        HStack(spacing: 20) {
                            // Like
                            Button(action: {
                                viewModel.toggleLike(for: tweet)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: tweet.isFavorited ? "heart.fill" : "heart")
                                        .font(.system(size: 12))
                                    if tweet.favoriteCount > 0 {
                                        Text("\(tweet.favoriteCount)")
                                            .font(theme.appFont(size: 11))
                                    }
                                }
                                .foregroundColor(tweet.isFavorited ? Color(hex: "#F91880") : ThemeManager.secondaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Retweet & Quote Menu (右边)
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
                                            .font(theme.appFont(size: 11))
                                    }
                                }
                                .foregroundColor(tweet.isRetweeted ? Color(hex: "#00BA7C") : ThemeManager.secondaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // A reply to another reply sits one tab in
            .padding(.leading, CGFloat(depth) * 28)
            .overlay(alignment: .topLeading) {
                // A straight line from the avatar of the reply being answered down to the reply that answers it.
                // Avatar: 16 from the edge, 36 wide, 8 below the row's top.
                ZStack(alignment: .topLeading) {
                    if linkAbove {
                        Rectangle()
                            .fill(ThemeManager.secondaryText.opacity(0.3))
                            .frame(width: 2, height: 8 + 18)
                            .padding(.leading, 16 + 18 + CGFloat(parentDepth) * 28 - 1)
                    }
                    if linkBelow {
                        Rectangle()
                            .fill(ThemeManager.secondaryText.opacity(0.3))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .padding(.top, 8 + 36 + 3)
                            .padding(.leading, 16 + 18 + CGFloat(depth) * 28 - 1)
                    }
                }
                .allowsHitTesting(false)
            }
            
            // The line carries on into the next row, so no divider between a reply and the one answering it
            if !linkBelow {
                Rectangle()
                    .fill(ThemeManager.divider.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.leading, 62 + CGFloat(depth) * 28)
            }
        }
    }
    
    // MARK: - Bottom Floating Reply Dock (Dual-Mode: Liquid Glass Capsule vs Classic Frosted Glass)
    @ViewBuilder
    private var bottomReplyDock: some View {
        if theme.useLiquidGlass {
            liquidGlassReplyDock
        } else {
            frostedGlassReplyDock
        }
    }
    
    // Mode A: Native Liquid Glass Capsule Reply Dock (macOS 26+ Glass API, specular border, floating capsule)
    private var liquidGlassReplyDock: some View {
        HStack(spacing: 10) {
            // The signed-in account's own picture
            CurrentUserAvatar(size: 30)
            
            // Text Input Field Container (inset liquid glass track)
            HStack(spacing: 6) {
                TextField(loc.t("reply_placeholder"), text: $viewModel.quickReplyText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.appFont(size: 13))
                    .foregroundColor(ThemeManager.primaryText)
                    .focused($isDockInputFocused)
                    .onSubmit {
                        viewModel.postQuickReply()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.07))
                    .overlay(
                        Capsule().stroke(theme.isLight ? Color(hex: "#DED9CB").opacity(0.6) : Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            
            // Submit Button
            if !viewModel.quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: {
                    viewModel.postQuickReply()
                }) {
                    if viewModel.isSubmittingReply {
                        LoadingIndicator(compactHeight: 22)
                    } else {
                        Group {
                            if #available(macOS 26.0, *) {
                                Text(loc.t("post_reply"))
                                    .font(theme.appFont(size: 12, weight: .bold))
                                    .foregroundColor(ThemeManager.onAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(ThemeManager.accent.opacity(0.85))
                                            .tweetGlass(.regular.tint(ThemeManager.accent.opacity(0.25)).interactive(), in: Capsule())
                                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                                    )
                            } else {
                                Text(loc.t("post_reply"))
                                    .font(theme.appFont(size: 12, weight: .bold))
                                    .foregroundColor(ThemeManager.onAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(ThemeManager.accent))
                            }
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            Group {
                if #available(macOS 26.0, *) {
                    let glassStyle: Glass = theme.useLiquidGlassTint
                        ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.18)).interactive()
                        : .regular.interactive()
                    Capsule()
                        .fill(theme.isLight ? Color.white.opacity(0.68) : Color.black.opacity(0.24))
                        .tweetGlass(glassStyle, in: Capsule())
                } else {
                    Capsule()
                        .fill(theme.isLight ? Color.white.opacity(0.85) : Color.black.opacity(0.5))
                }
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    theme.isLight ? Color(hex: "#DED9CB").opacity(0.85) : Color.white.opacity(0.22),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.35), radius: 14, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // Mode B: Classic Frosted Glass Reply Dock (Gaussian Blur when Liquid Glass is off)
    private var frostedGlassReplyDock: some View {
        HStack(spacing: 10) {
            // The signed-in account's own picture
            CurrentUserAvatar(size: 30)
            
            // Text Input Field
            TextField(loc.t("reply_placeholder"), text: $viewModel.quickReplyText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(theme.appFont(size: 13))
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
                        LoadingIndicator(compactHeight: 22)
                    } else {
                        Text(loc.t("post_reply"))
                            .font(theme.appFont(size: 12, weight: .bold))
                            .foregroundColor(ThemeManager.onAccent)
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
    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
    
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
