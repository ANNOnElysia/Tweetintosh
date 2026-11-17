//
//  ProfileView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  User profile page: a tall banner with the identity and follower stats on it, which collapses into the
//  Liquid Glass bar as you scroll; then bio details and Posts / Media / Replies tabs.
//

import SwiftUI
import AppKit

// Only flips when the header crosses under the bar, so scrolling doesn't re-render the whole page
private final class ProfileChromeState: ObservableObject {
    @Published var isCollapsed = false
    // Page width, for sizing the media grid's square cells explicitly (a List measures a row's height before
    // aspect-ratio sizing applies, so self-sizing squares would overlap)
    @Published var contentWidth: CGFloat = 0
    // Not published: the page must not redraw on every pull, only the spinner does
    let pull = DetailPullController()
}

// The spinner that follows a pull over the stretching banner, and stays while the profile refreshes
private struct ProfilePullIndicator: View {
    @ObservedObject var pull: DetailPullController
    @ObservedObject var vm: ProfileViewModel
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if vm.isRefreshing || pull.pullDistance > 2 {
            let distance = vm.isRefreshing ? 40.0 : pull.pullDistance
            let progress = vm.isRefreshing ? 1.0 : min(1.0, max(0.0, distance / TrackpadPullCoordinator.refreshThreshold))
            SVGRefreshIndicatorView(pullProgress: progress, isRefreshing: vm.isRefreshing, colorScheme: theme.themeColor)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .offset(y: 62 + (distance - 40.0) / 2.0)
                .opacity(vm.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(distance - 2.0) / 8.0)))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Profile Page

struct ProfileView: View {
    let onDismiss: () -> Void
    @StateObject private var vm: ProfileViewModel
    @StateObject private var chrome = ProfileChromeState()
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let nav = NavigationManager.shared
    @Namespace private var tabNamespace

    private let bannerHeight: CGFloat = 250
    private static let bannerFadeHeight: CGFloat = 96
    private static let bannerCornerRadius: CGFloat = 22

    init(user: TweetUser, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ProfileViewModel(user: user))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()

            ScrollContainer(onScrollView: { chrome.pull.attach($0) }, onNearBottom: { vm.loadTab(vm.selectedTab, more: true) }) {
                header
                    .reportsListScrollView()
                details
                tabBar
                tabContent
            }
            .coordinateSpace(name: "profileScroll")
            .ignoresSafeArea(edges: .top)

            ProfilePullIndicator(pull: chrome.pull, vm: vm)

            topBar
        }
        .onAppear {
            if !ProfileViewModel.live.contains(where: { $0 === vm }) { ProfileViewModel.live.append(vm) }
            vm.load()
            chrome.pull.onTrigger = { [weak vm] in vm?.refresh() }
        }
        .onChange(of: vm.isRefreshing) {
            chrome.pull.isBusy = vm.isRefreshing
        }
        // Command+R refreshes the page in front, as it does the timeline and a post
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_RefreshTimeline"))) { _ in
            if case .profile(let shown)? = nav.overlayStack.last?.page,
               shown.screenName.caseInsensitiveCompare(vm.user.screenName) == .orderedSame {
                vm.refresh()
            }
        }
        .onDisappear {
            ProfileViewModel.live.removeAll { $0 === vm }
        }
    }

    // MARK: Header (banner, identity, stats)

    private var header: some View {
        GeometryReader { geo in
            // Pulling down past the top stretches the banner instead of revealing a gap
            let stretch = max(0, geo.frame(in: .named("profileScroll")).minY)
            ZStack(alignment: .bottom) {
                // Fades in from the top, so the window's top edge and the floating back and edit buttons sit on the page's
                // own background rather than on a hard image edge. A fixed fade length, so stretching doesn't lengthen it.
                banner
                    .frame(width: geo.size.width, height: bannerHeight + stretch)
                    .clipped()
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: Self.bannerFadeHeight)
                            Color.black
                        }
                    )

                LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 12) {
                    identity
                    Spacer(minLength: 12)
                    // The counts keep their full size; when room is short the name truncates instead of the pills wrapping
                    statPills
                        .fixedSize()
                        .layoutPriority(1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width, height: bannerHeight + stretch)
            // Rounded on both sides of its lower edge, with the same radius as the sidebar's glass beside it
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.bannerCornerRadius,
                                              bottomTrailingRadius: Self.bannerCornerRadius, style: .continuous))
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
                        .font(theme.appFont(size: 21, weight: .bold))
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
                HStack(spacing: 6) {
                    Text(vm.user.formattedHandle)
                        .font(theme.appFont(size: 13.5))
                        .opacity(0.82)
                        .lineLimit(1)
                    // As on X: beside the handle, only on other people's profiles
                    if vm.profile?.followsYou == true && !vm.isOwnProfile {
                        Text(loc.t("profile_follows_you"))
                            .font(theme.appFont(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
                    }
                }
            }
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
        }
    }

    // Following / followers as glass pills on the banner, opposite the identity
    private var statPills: some View {
        HStack(spacing: 8) {
            if let following = vm.user.followingCount {
                statPill(following, loc.t("peek_following"), opens: .following)
            }
            if let followers = vm.user.followersCount {
                statPill(followers, loc.t("peek_followers"), opens: .followers)
            }
        }
    }

    // Each count opens the people it counts, as on X
    private func statPill(_ count: Int, _ label: String, opens kind: TweetUsersKind) -> some View {
        Button {
            NavigationManager.shared.openUserList(kind, tweetId: vm.userId)
        } label: {
            statPillLabel(count, label)
        }
        .buttonStyle(.target)
        // The account's id arrives with the profile when the page was opened from just a handle
        .disabled(vm.userId.isEmpty)
        .help(label)
    }

    private func statPillLabel(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            // Semantic styles rather than the theme's fixed colours, whose gray washes out on bare glass over a banner
            Text(Self.formatCount(count))
                .font(theme.appFont(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(theme.appFont(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
    }

    // MARK: Details (bio, location, website, joined)

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let bio = vm.user.bio, !bio.isEmpty {
                // Long bios fold after 6 lines, with "Show more" underneath
                FoldableText(limit: 6) {
                    LinkedText.make(bio, links: vm.user.bioLinks ?? [])
                        .font(theme.tweetFont(size: 14.5))
                        .lineSpacing(theme.lineSpacing())
                        .foregroundColor(ThemeManager.primaryText)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 16) {
                if let location = vm.user.location, !location.isEmpty {
                    metaItem("mappin.and.ellipse", Text(location))
                }
                if let website = vm.profile?.websiteDisplay, let url = vm.profile?.websiteUrl {
                    Link(destination: url) {
                        metaItem("link", Text(website).foregroundColor(ThemeManager.accent))
                    }
                    .buttonStyle(.target)
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
                Group {
                    HStack(spacing: 5) {
                        Text(loc.t("profile_tab_\(tab.rawValue)"))
                            .font(theme.appFont(size: 13, weight: selected ? .semibold : .regular))
                        
                        // Shortcut hint, revealed while ⌘ is held
                        if nav.showShortcutBadges {
                            Text(tab.shortcutKey)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(selected ? ThemeManager.accent.opacity(0.9) : ThemeManager.tertiaryText)
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(selected ? ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.16) : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
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
                        .contentShape(Rectangle())
                }
                .pressDragItem(tab)
            }
        }
        .pressDragSelection { (tab: ProfileTab) in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                vm.select(tab)
            }
        }
        .padding(4)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule(), isClear: true, isInteractive: false))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Divider().background(ThemeManager.divider)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if abs(chrome.contentWidth - width) > 0.5 { chrome.contentWidth = width }
        }
    }

    @ViewBuilder private var tabContent: some View {
        let tab = vm.selectedTab
        let list = vm.tweets[tab] ?? []

        if list.isEmpty {
            Group {
                if vm.loadingTabs.contains(tab) || vm.tweets[tab] == nil && !vm.failedTabs.contains(tab) {
                    LoadingIndicator()
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
            // Rows of three cells: each row is its own list row, so the grid stays lazy inside a List too
            let cells = list.filter { !$0.tweet.media.isEmpty }
            let side = max(1, floor((chrome.contentWidth - 12) / 3))
            ForEach(Array(stride(from: 0, to: cells.count, by: 3)), id: \.self) { start in
                HStack(spacing: 3) {
                    ForEach(start..<min(start + 3, cells.count), id: \.self) { index in
                        ProfileMediaCell(tweet: cells[index].tweet)
                            .frame(width: side, height: side)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: side)
                .padding(.horizontal, 3)
                .padding(.top, start == 0 ? 3 : 0)
                .padding(.bottom, 3)
            }
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
            LoadingIndicator(active: vm.loadingTabs.contains(tab))
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .help("\(loc.t("nav_back")) (Esc / ←)")

            // Collapsed identity: avatar, name, and follower count once the banner scrolls away
            if chrome.isCollapsed {
                HStack(spacing: 8) {
                    CachedAsyncImage(urlString: vm.user.avatarUrl, targetSize: CGSize(width: 26, height: 26))
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.user.name)
                            .font(theme.appFont(size: 13, weight: .semibold))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(1)
                        if let followers = vm.user.followersCount {
                            Text("\(Self.formatCount(followers)) \(loc.t("peek_followers"))")
                                .font(theme.appFont(size: 11))
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

            if vm.isOwnProfile {
                editProfileButton
            } else {
                followButton
                moreMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var moreMenu: some View {
        Menu {
            Menu(loc.t("profile_add_to_list")) {
                if let lists = vm.ownedLists {
                    if lists.isEmpty {
                        Text(loc.t("profile_no_lists"))
                    }
                    ForEach(lists) { list in
                        Toggle(list.name, isOn: Binding(get: { list.isMember }, set: { _ in vm.toggleList(list) }))
                    }
                } else {
                    Text(loc.t(vm.listsFailed ? "profile_lists_failed" : "profile_lists_loading"))
                }
            }
            Divider()
            Button(loc.format(vm.isMuting ? "profile_menu_unmute" : "post_menu_mute", ["handle": vm.user.formattedHandle]),
                   action: vm.toggleMute)
            if vm.isBlocking {
                Button(loc.format("profile_menu_unblock", ["handle": vm.user.formattedHandle]), action: vm.toggleBlock)
            } else {
                Button(loc.format("post_menu_block", ["handle": vm.user.formattedHandle]), role: .destructive) {
                    vm.isConfirmingBlock = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        // The borderless style flattens its label into a dimmed, left-aligned image; this one draws the view as it is.
        // A menu passes over the app's own .target style and falls back to the system's bordered box, drawn around
        // the round glass; the plain style draws nothing of its own. The label is already the 36-point target.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Circle()))
        .help(loc.t("profile_more"))
        .onHover { if $0 { vm.loadOwnedListsIfNeeded() } }
        .alert(loc.format("post_menu_block", ["handle": vm.user.formattedHandle]), isPresented: $vm.isConfirmingBlock) {
            Button(loc.t("profile_block_confirm"), role: .destructive, action: vm.toggleBlock)
            Button(loc.t("cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("profile_block_message"))
        }
    }

    private var editProfileButton: some View {
        Button { vm.isEditing = true } label: {
            Text(loc.t("edit_profile"))
                .font(theme.appFont(size: 13, weight: .semibold))
                .foregroundColor(ThemeManager.primaryText)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
        }
        .buttonStyle(.target)
        .disabled(vm.profile == nil)
        .help(loc.t("edit_profile"))
        .sheet(isPresented: $vm.isEditing) {
            if let profile = vm.profile {
                EditProfileView(profile: profile) { vm.reloadProfile() }
            }
        }
    }

    @ViewBuilder private var followButton: some View {
        if vm.isBlockedByUser {
            // They've blocked you: you can still read everything, but not follow. A tap explains why.
            Button(action: vm.toggleFollow) {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                    Text(loc.t("profile_blocked"))
                        .font(theme.appFont(size: 13, weight: .semibold))
                }
                .foregroundColor(ThemeManager.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
            }
            .buttonStyle(.target)
            .help(loc.format("profile_blocked_follow", ["name": vm.user.formattedHandle]))
        } else {
            Button(action: vm.toggleFollow) {
                Text(loc.t(vm.isFollowing ? "profile_following_button" : "profile_follow"))
                    .font(theme.appFont(size: 13, weight: .semibold))
                    .foregroundColor(vm.isFollowing ? ThemeManager.primaryText : ThemeManager.onAccent)
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
            .buttonStyle(.target)
            .disabled(vm.profile == nil && vm.user.id.isEmpty)
            .help(vm.isFollowing ? loc.t("profile_unfollow") : loc.t("profile_follow"))
        }
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
            .navigationPointer()
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
            .navigationPointer()
            .onTapGesture {
                NavigationManager.shared.openProfile(user)
            }
            // Warm the profile once the pointer rests here, like X's hover card does
            .preloadOnHover(kind: "profile", key: user.screenName, delay: 0.2) {
                ProfilePreloader.shared.preload(user)
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

// MARK: - Foldable Text

private final class FoldState: ObservableObject {
    @Published var isExpanded = false
    // True once the text is seen to need more than `limit` lines; stays true after expanding so "Show less" remains
    @Published var canFold = false
    var fullHeight: CGFloat = 0
    var visibleHeight: CGFloat = 0
    
    func recompute() {
        guard !isExpanded else { return }
        let overflows = fullHeight - visibleHeight > 1
        if overflows != canFold { canFold = overflows }
    }
}

// Shows its content limited to `limit` lines; if it needs more, a "Show more" button unfolds it. Overflow is found
// by measuring a hidden unlimited copy against the limited one.
struct FoldableText<Content: View>: View {
    let limit: Int
    @ViewBuilder let content: () -> Content
    @StateObject private var fold = FoldState()
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .lineLimit(fold.isExpanded ? nil : limit)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    fold.visibleHeight = height
                    fold.recompute()
                }
                .background(
                    content()
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            fold.fullHeight = height
                            fold.recompute()
                        }
                )
            
            if fold.canFold {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        fold.isExpanded.toggle()
                    }
                } label: {
                    Text(loc.t(fold.isExpanded ? "profile_show_less" : "profile_show_more"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.target)
                .navigationPointer()
            }
        }
    }
}
