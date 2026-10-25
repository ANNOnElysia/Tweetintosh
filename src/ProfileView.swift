//
//  ProfileView.swift
//  MaX - Headless Data-driven Client
//
//  User profile page: a tall banner with the identity and follower stats on it, which collapses into the
//  Liquid Glass bar as you scroll; then bio details and Posts / Media / Replies tabs.
//

import SwiftUI
import AppKit

// MARK: - View Model

final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: TweetUser
    @Published private(set) var profile: UserProfile?
    @Published private(set) var selectedTab: ProfileTab = .posts
    @Published private(set) var tweets: [ProfileTab: [ProfileTimelineItem]] = [:]
    @Published private(set) var loadingTabs: Set<ProfileTab> = []
    @Published private(set) var failedTabs: Set<ProfileTab> = []
    @Published private(set) var isFollowing = false
    @Published private(set) var isFollowBusy = false

    private var cursors: [ProfileTab: String] = [:]
    private var exhausted: Set<ProfileTab> = []

    init(user: TweetUser) {
        // The tweet's author data (name, avatar, bio, banner, counts) renders the header right away
        self.user = user
    }

    var userId: String { profile?.user.id ?? user.id }

    func hasMore(_ tab: ProfileTab) -> Bool {
        tweets[tab] != nil && !exhausted.contains(tab)
    }

    func load() {
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let profile) = result {
                    self.profile = profile
                    self.user = profile.user
                    self.isFollowing = profile.isFollowing
                }
                if self.tweets[self.selectedTab] == nil && !self.loadingTabs.contains(self.selectedTab) {
                    self.loadTab(self.selectedTab)
                }
            }
        }
        // Authors from tweets carry their id, so posts can load alongside the profile
        if !user.id.isEmpty {
            loadTab(.posts)
        }
    }

    func select(_ tab: ProfileTab) {
        selectedTab = tab
        if tweets[tab] == nil {
            loadTab(tab)
        }
    }

    func loadTab(_ tab: ProfileTab, more: Bool = false) {
        guard !loadingTabs.contains(tab), !userId.isEmpty else { return }
        if more && (exhausted.contains(tab) || cursors[tab] == nil) { return }
        loadingTabs.insert(tab)
        failedTabs.remove(tab)

        APIClient.shared.fetchUserTimeline(tab, userId: userId, cursor: more ? cursors[tab] : nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingTabs.remove(tab)
                switch result {
                case .success(let page):
                    var list = more ? (self.tweets[tab] ?? []) : []
                    let existing = Set(list.map { $0.id })
                    let fresh = page.items.filter { !existing.contains($0.id) }
                    list.append(contentsOf: fresh)
                    self.tweets[tab] = list
                    self.cursors[tab] = page.bottomCursor
                    if fresh.isEmpty || page.bottomCursor == nil {
                        self.exhausted.insert(tab)
                    }
                case .failure:
                    self.failedTabs.insert(tab)
                }
            }
        }
    }

    func toggleFollow() {
        guard !isFollowBusy, !userId.isEmpty else { return }
        let target = !isFollowing
        isFollowing = target
        isFollowBusy = true
        APIClient.shared.setFollowing(target, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFollowBusy = false
                if case .failure = result {
                    self.isFollowing = !target
                }
            }
        }
    }
}

// Only flips when the header crosses under the bar, so scrolling doesn't re-render the whole page
private final class ProfileChromeState: ObservableObject {
    @Published var isCollapsed = false
}

// MARK: - Profile Page

struct ProfileView: View {
    let onDismiss: () -> Void
    @StateObject private var vm: ProfileViewModel
    @StateObject private var chrome = ProfileChromeState()
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Namespace private var tabNamespace

    private let bannerHeight: CGFloat = 250

    init(user: TweetUser, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ProfileViewModel(user: user))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    details
                    tabBar
                    tabContent
                }
            }
            .coordinateSpace(name: "profileScroll")
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .onAppear {
            vm.load()
        }
    }

    // MARK: Header (banner, identity, stats)

    private var header: some View {
        GeometryReader { geo in
            // Pulling down past the top stretches the banner instead of revealing a gap
            let stretch = max(0, geo.frame(in: .named("profileScroll")).minY)
            ZStack(alignment: .bottom) {
                banner
                    .frame(width: geo.size.width, height: bannerHeight + stretch)
                    .clipped()

                LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 12) {
                    identity
                    Spacer(minLength: 12)
                    statPills
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width, height: bannerHeight + stretch)
            .offset(y: -stretch)
        }
        .frame(height: bannerHeight)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named("profileScroll")).maxY < 96
        } action: { collapsed in
            if chrome.isCollapsed != collapsed {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    chrome.isCollapsed = collapsed
                }
            }
        }
    }

    @ViewBuilder private var banner: some View {
        if let bannerUrl = vm.user.bannerUrl {
            CachedAsyncImage(
                urlString: bannerUrl + "/1500x500",
                placeholderColor: ThemeManager.accent.opacity(0.25),
                targetSize: CGSize(width: 1000, height: bannerHeight)
            )
        } else {
            ThemeManager.accent.opacity(0.3)
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 12) {
            CachedAsyncImage(
                urlString: vm.user.avatarUrl?.replacingOccurrences(of: "_bigger", with: "_400x400"),
                targetSize: CGSize(width: 76, height: 76)
            )
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2.5))
            .peekable(.profile(vm.user))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(vm.user.name)
                        .font(.system(size: 21, weight: .bold))
                        .lineLimit(1)
                    if vm.user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundColor(ThemeManager.accent)
                    }
                    if vm.profile?.isProtected == true {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                    }
                }
                Text(vm.user.formattedHandle)
                    .font(.system(size: 13.5))
                    .opacity(0.82)
            }
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
        }
    }

    // Following / followers as glass pills on the banner, opposite the identity
    private var statPills: some View {
        HStack(spacing: 8) {
            if let following = vm.user.followingCount {
                statPill(following, loc.t("peek_following"))
            }
            if let followers = vm.user.followersCount {
                statPill(followers, loc.t("peek_followers"))
            }
        }
    }

    private func statPill(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(Self.formatCount(count))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(ThemeManager.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
    }

    // MARK: Details (bio, location, website, joined)

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let bio = vm.user.bio, !bio.isEmpty {
                LinkedText.make(bio, links: vm.user.bioLinks ?? [])
                    .font(theme.tweetFont(size: 14.5))
                    .lineSpacing(theme.lineSpacing())
                    .foregroundColor(ThemeManager.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                if let location = vm.user.location, !location.isEmpty {
                    metaItem("mappin.and.ellipse", Text(location))
                }
                if let website = vm.profile?.websiteDisplay, let url = vm.profile?.websiteUrl {
                    Link(destination: url) {
                        metaItem("link", Text(website).foregroundColor(ThemeManager.accent))
                    }
                    .buttonStyle(.plain)
                }
                if let joined = vm.profile?.joinedAt {
                    metaItem("calendar", Text(loc.format("profile_joined", ["date": Self.joinedFormatter().string(from: joined)])))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private func metaItem(_ icon: String, _ text: Text) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            text
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .foregroundColor(ThemeManager.secondaryText)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(ProfileTab.allCases) { tab in
                let selected = vm.selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        vm.select(tab)
                    }
                } label: {
                    Text(loc.t("profile_tab_\(tab.rawValue)"))
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? ThemeManager.accent : ThemeManager.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.2))
                                    .matchedGeometryEffect(id: "profile-tab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule(), isClear: true))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Divider().background(ThemeManager.divider)
        }
    }

    @ViewBuilder private var tabContent: some View {
        let tab = vm.selectedTab
        let list = vm.tweets[tab] ?? []

        if list.isEmpty {
            Group {
                if vm.loadingTabs.contains(tab) || vm.tweets[tab] == nil && !vm.failedTabs.contains(tab) {
                    GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 20)
                } else if vm.failedTabs.contains(tab) {
                    VStack(spacing: 10) {
                        Text(loc.t("profile_load_failed"))
                            .font(.system(size: 13.5))
                            .foregroundColor(ThemeManager.secondaryText)
                        Button(loc.t("profile_retry")) { vm.loadTab(tab) }
                    }
                } else {
                    Text(loc.t(vm.profile?.isProtected == true ? "profile_protected" : "profile_empty"))
                        .font(.system(size: 13.5))
                        .foregroundColor(ThemeManager.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if tab == .media {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(list.filter { !$0.tweet.media.isEmpty }) { item in
                    ProfileMediaCell(tweet: item.tweet)
                }
            }
            .padding(3)
            footer(for: tab)
        } else {
            ForEach(list) { item in
                TweetRowView(tweet: item.tweet, threadAbove: item.threadAbove, threadBelow: item.threadBelow)
            }
            footer(for: tab)
        }
    }

    @ViewBuilder private func footer(for tab: ProfileTab) -> some View {
        if vm.hasMore(tab) {
            GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 16)
                .opacity(vm.loadingTabs.contains(tab) ? 1 : 0)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .onAppear { vm.loadTab(tab, more: true) }
        } else {
            Color.clear.frame(height: 30)
        }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                    .frame(width: 36, height: 36)
                    .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Circle()))
            }
            .buttonStyle(.plain)
            .help("\(loc.t("nav_back")) (Esc / ←)")

            // Collapsed identity: avatar, name, and follower count once the banner scrolls away
            if chrome.isCollapsed {
                HStack(spacing: 8) {
                    CachedAsyncImage(urlString: vm.user.avatarUrl, targetSize: CGSize(width: 26, height: 26))
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.user.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(1)
                        if let followers = vm.user.followersCount {
                            Text("\(Self.formatCount(followers)) \(loc.t("peek_followers"))")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeManager.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 5)
                .padding(.trailing, 14)
                .frame(height: 36)
                .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
                .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }

            Spacer()

            followButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var followButton: some View {
        Button(action: vm.toggleFollow) {
            Text(loc.t(vm.isFollowing ? "profile_following_button" : "profile_follow"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(vm.isFollowing ? ThemeManager.primaryText : .white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background {
                    if !vm.isFollowing {
                        Capsule().fill(ThemeManager.accent)
                    }
                }
                .modifier(FollowGlass(enabled: vm.isFollowing, isLiquid: theme.useLiquidGlass))
                .opacity(vm.isFollowBusy ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(vm.profile == nil && vm.user.id.isEmpty)
        .help(vm.isFollowing ? loc.t("profile_unfollow") : loc.t("profile_follow"))
    }

    // MARK: Formatting

    static func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1_000.0) }
        return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    private static func joinedFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        switch LocalizationManager.shared.currentLanguage {
        case .english: formatter.locale = Locale(identifier: "en_US")
        case .japanese: formatter.locale = Locale(identifier: "ja_JP")
        case .korean: formatter.locale = Locale(identifier: "ko_KR")
        case .simplifiedChinese: formatter.locale = Locale(identifier: "zh_Hans_CN")
        case .traditionalChinese: formatter.locale = Locale(identifier: "zh_Hant_TW")
        }
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }
}

// Glass only for the "Following" state; "Follow" is a solid accent capsule
private struct FollowGlass: ViewModifier {
    let enabled: Bool
    let isLiquid: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.modifier(AdaptiveGlassModifier(isLiquid: isLiquid, shape: Capsule()))
        } else {
            content
        }
    }
}

// MARK: - Media Grid Cell

// Clicking a cell opens its post; a deep press previews the image or video
private struct ProfileMediaCell: View {
    let tweet: Tweet

    var body: some View {
        let media = tweet.media[0]
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                CachedAsyncImage(
                    urlString: MediaCacheManager.shared.formatThumbUrl(media.mediaUrl),
                    contentMode: .fill,
                    targetSize: CGSize(width: 300, height: 300)
                )
            )
            .clipped()
            .overlay(alignment: .topTrailing) {
                if tweet.media.count > 1 || media.isVideo {
                    Image(systemName: media.isVideo ? "play.fill" : "square.on.square")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.5), radius: 2)
                        .padding(7)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NavigationManager.shared.openTweetDetail(tweet)
            }
            .mediaContextMenu(media: media, tweet: tweet)
            .peekable(media.isVideo ? .video(media) : .image(media))
    }
}

// MARK: - Entry Point

extension View {
    // Tapping an avatar, name or handle opens that user's profile page
    func opensProfile(_ user: TweetUser) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture {
                NavigationManager.shared.openProfile(user)
            }
    }
}

// MARK: - Linked Text

enum LinkedText {
    // Replaces t.co links with their display URL and makes them clickable, in the accent colour
    static func make(_ text: String, links: [TweetLink]) -> Text {
        guard !links.isEmpty else { return Text(text) }
        var display = text
        var ranges: [(NSRange, String)] = []
        var searchFrom = 0
        for link in links {
            let ns = display as NSString
            let found = ns.range(of: link.url, range: NSRange(location: searchFrom, length: ns.length - searchFrom))
            guard found.location != NSNotFound else { continue }
            display = ns.replacingCharacters(in: found, with: link.displayUrl)
            let range = NSRange(location: found.location, length: (link.displayUrl as NSString).length)
            ranges.append((range, link.expandedUrl))
            searchFrom = range.location + range.length
        }
        var attributed = AttributedString(display)
        for (range, url) in ranges {
            guard let r = Range(range, in: display), let ar = Range(r, in: attributed) else { continue }
            attributed[ar].foregroundColor = ThemeManager.accent
            attributed[ar].link = URL(string: url)
        }
        return Text(attributed)
    }
}
