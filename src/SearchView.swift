//
//  SearchView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Search results page: an editable glass search field, a glass tab capsule (Top / Latest / People),
//  and the results below, reusing the timeline's post rows and the profile page's navigation.
//

import SwiftUI
import AppKit

// MARK: - View Model

final class SearchViewModel: ObservableObject, TweetMutationTarget {
    // The search page currently on screen, for the keyboard shortcuts
    static weak var current: SearchViewModel?
    
    @Published private(set) var query: String
    // What's typed in the search field, which can differ from the query being shown
    @Published var draft: String
    @Published private(set) var selectedTab: SearchTab = .top
    @Published private(set) var tweets: [SearchTab: [Tweet]] = [:]
    @Published private(set) var users: [TweetUser] = []
    @Published private(set) var loadingTabs: Set<SearchTab> = []
    @Published private(set) var failedTabs: Set<SearchTab> = []

    private var cursors: [SearchTab: String] = [:]
    private var exhausted: Set<SearchTab> = []
    private var loaded: Set<SearchTab> = []
    // Bumped on every new search so a slow reply for an old query can't overwrite newer results
    private var generation = 0

    init(query: String) {
        self.query = query
        self.draft = query
        TweetMutationHub.shared.register(self)
    }

    func isLoaded(_ tab: SearchTab) -> Bool { loaded.contains(tab) }
    func hasMore(_ tab: SearchTab) -> Bool { loaded.contains(tab) && !exhausted.contains(tab) }

    func start() {
        loadTab(selectedTab)
    }

    func submit(_ newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        generation += 1
        query = trimmed
        SearchRecents.shared.add(trimmed)
        tweets = [:]
        users = []
        cursors = [:]
        exhausted = []
        loaded = []
        loadingTabs = []
        failedTabs = []
        loadTab(selectedTab)
    }

    // ⌥⌘← / ⌥⌘→
    func stepTab(_ delta: Int) {
        let all = SearchTab.allCases
        guard let index = all.firstIndex(of: selectedTab) else { return }
        let next = index + delta
        if all.indices.contains(next) { select(all[next]) }
    }
    
    func select(_ tab: SearchTab) {
        selectedTab = tab
        if !loaded.contains(tab) && !loadingTabs.contains(tab) {
            loadTab(tab)
        }
    }

    func loadTab(_ tab: SearchTab, more: Bool = false) {
        guard !loadingTabs.contains(tab) else { return }
        if more && (exhausted.contains(tab) || cursors[tab] == nil) { return }
        loadingTabs.insert(tab)
        failedTabs.remove(tab)
        let myGeneration = generation

        APIClient.shared.fetchSearch(query: query, tab: tab, cursor: more ? cursors[tab] : nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.generation == myGeneration else { return }
                self.loadingTabs.remove(tab)
                switch result {
                case .success(let page):
                    self.loaded.insert(tab)
                    var fresh = 0
                    if tab == .people {
                        let existing = Set(self.users.map { $0.id })
                        let added = page.users.filter { !existing.contains($0.id) }
                        self.users.append(contentsOf: added)
                        fresh = added.count
                    } else {
                        var list = more ? (self.tweets[tab] ?? []) : []
                        let existing = Set(list.map { $0.id })
                        let added = page.tweets.filter { !existing.contains($0.id) }
                        list.append(contentsOf: added)
                        self.tweets[tab] = list
                        fresh = added.count
                    }
                    self.cursors[tab] = page.bottomCursor
                    if fresh == 0 || page.bottomCursor == nil {
                        self.exhausted.insert(tab)
                    }
                case .failure:
                    self.failedTabs.insert(tab)
                }
            }
        }
    }

    // Keeps results in step with likes, reposts, and bookmarks made anywhere
    func applyMutation(id: String, transform: (inout Tweet) -> Void) {
        for tab in Array(tweets.keys) {
            guard var list = tweets[tab] else { continue }
            var changed = false
            for index in list.indices where list[index].canonicalId == id {
                transform(&list[index])
                changed = true
            }
            if changed { tweets[tab] = list }
        }
    }
}

// MARK: - Search Page

struct SearchView: View {
    let onDismiss: () -> Void
    @StateObject private var vm: SearchViewModel
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var nav = NavigationManager.shared
    @Namespace private var tabNamespace
    @FocusState private var isFieldFocused: Bool

    init(query: String, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: SearchViewModel(query: query))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()

            // Room for the floating search bar and tab capsule
            ScrollContainer(topSpacer: 108, onNearBottom: { vm.loadTab(vm.selectedTab, more: true) }) {
                results
            }

            VStack(spacing: 10) {
                topBar
                tabBar
            }
            .padding(.top, 10)
        }
        .onAppear {
            SearchViewModel.current = vm
            vm.start()
        }
        .onDisappear {
            if SearchViewModel.current === vm { SearchViewModel.current = nil }
        }
    }

    // MARK: Top bar (back + editable search field)

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

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ThemeManager.accent)

                TextField(loc.t("search_placeholder"), text: $vm.draft)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(theme.appFont(size: 13.5))
                    .foregroundColor(ThemeManager.primaryText)
                    .focused($isFieldFocused)
                    .onSubmit {
                        vm.submit(vm.draft)
                    }

                if !vm.draft.isEmpty {
                    Button {
                        vm.draft = ""
                        isFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
        }
        .padding(.horizontal, 16)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SearchTab.allCases) { tab in
                let selected = vm.selectedTab == tab
                Group {
                    HStack(spacing: 5) {
                        Text(loc.t("search_tab_\(tab.rawValue)"))
                            .font(theme.appFont(size: 13, weight: selected ? .semibold : .regular))
                        
                        // Shortcut hint, revealed while ⌘ is held (as on the Notifications filters)
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
                                    .matchedGeometryEffect(id: "search-tab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .pressDragItem(tab)
            }
        }
        .pressDragSelection { (tab: SearchTab) in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                vm.select(tab)
            }
        }
        .padding(4)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule(), isClear: true))
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let tab = vm.selectedTab
        let isEmpty = tab == .people ? vm.users.isEmpty : (vm.tweets[tab] ?? []).isEmpty

        if isEmpty {
            Group {
                if vm.failedTabs.contains(tab) {
                    VStack(spacing: 10) {
                        Text(loc.t("profile_load_failed"))
                            .font(.system(size: 13.5))
                            .foregroundColor(ThemeManager.secondaryText)
                        Button(loc.t("profile_retry")) { vm.loadTab(tab) }
                    }
                } else if vm.isLoaded(tab) {
                    Text(loc.format("search_no_results", ["query": vm.query]))
                        .font(.system(size: 13.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    LoadingIndicator()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
        } else if tab == .people {
            ForEach(vm.users) { user in
                SearchUserRow(user: user)
            }
            footer(for: tab)
        } else {
            ForEach(vm.tweets[tab] ?? []) { tweet in
                TweetRowView(tweet: tweet)
            }
            footer(for: tab)
        }
    }

    @ViewBuilder private func footer(for tab: SearchTab) -> some View {
        if vm.hasMore(tab) {
            LoadingIndicator(active: vm.loadingTabs.contains(tab))
                .frame(height: 50)
                .onAppear { vm.loadTab(tab, more: true) }
        } else {
            Color.clear.frame(height: 30)
        }
    }
}

// MARK: - People Row

private struct SearchUserRow: View {
    let user: TweetUser
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CachedAsyncImage(urlString: user.avatarUrl, targetSize: CGSize(width: 44, height: 44))
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                    .peekable(.profile(user))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(theme.appFont(size: 14.5, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(1)
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    Text(user.formattedHandle)
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(theme.appFont(size: 13))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                    if let followers = user.followersCount {
                        Text("\(ProfileView.formatCount(followers)) \(loc.t("peek_followers"))")
                            .font(theme.appFont(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(ThemeManager.divider)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NavigationManager.shared.openProfile(user)
        }
        .preloadOnHover(kind: "profile", key: user.screenName, delay: 0.2) {
            ProfilePreloader.shared.preload(user)
        }
    }
}
