//
//  ProfileViewModel.swift
//  Tweetintosh
//
//  The state and requests behind one profile page: the header, its tabs, and following, muting and blocking.
//

import SwiftUI
import os

private let preloadLogger = Logger(subsystem: "com.anno.tweetintosh", category: "preload")

final class ProfileViewModel: ObservableObject, TweetMutationTarget {
    @Published private(set) var user: TweetUser
    @Published private(set) var profile: UserProfile?
    @Published private(set) var selectedTab: ProfileTab = .posts
    @Published private(set) var tweets: [ProfileTab: [ProfileTimelineItem]] = [:]
    @Published private(set) var loadingTabs: Set<ProfileTab> = []
    @Published private(set) var failedTabs: Set<ProfileTab> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isFollowing = false
    @Published private(set) var isFollowBusy = false
    @Published private(set) var isMuting = false
    @Published private(set) var isBlocking = false
    // Nil until they have been fetched
    @Published private(set) var ownedLists: [OwnedList]?
    private var isLoadingLists = false
    // The menu says so rather than showing "Loading" for ever; the next hover tries again
    @Published private(set) var listsFailed = false
    @Published var isConfirmingBlock = false
    @Published var isEditing = false

    private var cursors: [ProfileTab: String] = [:]
    private var exhausted: Set<ProfileTab> = []

    // Profile pages currently on screen, oldest first, so the keyboard shortcuts reach the one in front
    // (even after another page above it is closed)
    static var live: [ProfileViewModel] = []

    // ⌥⌘← / ⌥⌘→
    func stepTab(_ delta: Int) {
        let all = ProfileTab.allCases
        guard let index = all.firstIndex(of: selectedTab) else { return }
        let next = index + delta
        if all.indices.contains(next) { select(all[next]) }
    }

    init(user: TweetUser) {
        // The tweet's author data (name, avatar, bio, banner, counts) renders the header right away
        self.user = user
        TweetMutationHub.shared.register(self)
    }

    // Keeps posts on this page in step with likes, reposts, and bookmarks made anywhere
    func applyMutation(id: String, transform: (inout Tweet) -> Void) {
        for tab in Array(tweets.keys) {
            guard var list = tweets[tab] else { continue }
            var changed = false
            for index in list.indices where list[index].tweet.canonicalId == id {
                transform(&list[index].tweet)
                changed = true
            }
            if changed { tweets[tab] = list }
        }
    }

    func removePost(id: String) {
        for tab in Array(tweets.keys) {
            guard let list = tweets[tab], list.contains(where: { $0.tweet.isCopy(ofPost: id) }) else { continue }
            tweets[tab] = list.filter { !$0.tweet.isCopy(ofPost: id) }
        }
    }

    var isBlockedByUser: Bool { user.hasBlockedYou }

    var userId: String { profile?.user.id ?? user.id }

    func hasMore(_ tab: ProfileTab) -> Bool {
        tweets[tab] != nil && !exhausted.contains(tab)
    }

    func load() {
        // A profile warmed by hovering opens already filled in; only what is missing is fetched
        var hasProfile = false
        if let preloaded = ProfilePreloader.shared.cached(user.screenName) {
            preloadLogger.notice("profile opened from preload cache @\(self.user.screenName, privacy: .public)")
            if let profile = preloaded.profile {
                self.profile = profile
                self.user = profile.user
                self.isFollowing = profile.isFollowing
                self.isMuting = profile.isMuting
                self.isBlocking = profile.isBlocking
                hasProfile = true
            }
            if let posts = preloaded.posts, tweets[.posts] == nil {
                tweets[.posts] = posts.items
                cursors[.posts] = posts.cursor
                if posts.cursor == nil || posts.items.isEmpty { exhausted.insert(.posts) }
                if hasProfile { return }
            }
            if hasProfile {
                loadTab(selectedTab)
                return
            }
        }
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let profile) = result {
                    self.profile = profile
                    self.user = profile.user
                    self.isFollowing = profile.isFollowing
                    self.isMuting = profile.isMuting
                    self.isBlocking = profile.isBlocking
                    // Posts loaded before the profile (their authors carry no block flag) re-check it now
                    self.objectWillChange.send()
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

    // After the profile was edited here: X is asked again, past the preload cache, and so are the sidebar's name and photo
    func reloadProfile() {
        ProfilePreloader.shared.forget(user.screenName)
        AccountManager.shared.refreshActiveInfo()
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let profile) = result else { return }
                self.profile = profile
                self.user = profile.user
            }
        }
    }

    // Pull-down or Command+R: the profile and the tab in view are asked for again, past the preload cache, so new posts
    // and changed counts show. The tab starts over from its newest page; other tabs reload when they are next opened.
    func refresh(minimumDuration: TimeInterval = 0.8) {
        guard !isRefreshing, !userId.isEmpty else { return }
        isRefreshing = true
        let started = Date()
        let tab = selectedTab
        let group = DispatchGroup()
        var freshProfile: UserProfile?
        var freshPage: (items: [ProfileTimelineItem], bottomCursor: String?)?

        ProfilePreloader.shared.forget(user.screenName)
        group.enter()
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { result in
            if case .success(let profile) = result { freshProfile = profile }
            group.leave()
        }
        group.enter()
        APIClient.shared.fetchUserTimeline(tab, userId: userId, cursor: nil) { result in
            if case .success(let page) = result { freshPage = (page.items, page.bottomCursor) }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if let profile = freshProfile {
                    self.profile = profile
                    self.user = profile.user
                    self.isFollowing = profile.isFollowing
                    self.isMuting = profile.isMuting
                    self.isBlocking = profile.isBlocking
                }
                // A failed fetch leaves the posts already on screen rather than emptying the page
                if let page = freshPage {
                    for other in ProfileTab.allCases where other != tab {
                        self.tweets[other] = nil
                        self.cursors[other] = nil
                        self.exhausted.remove(other)
                    }
                    self.tweets[tab] = page.items
                    self.cursors[tab] = page.bottomCursor
                    self.failedTabs.remove(tab)
                    if page.items.isEmpty || page.bottomCursor == nil {
                        self.exhausted.insert(tab)
                    } else {
                        self.exhausted.remove(tab)
                    }
                }
            }
            // The profile is already updated above; only the spinner waits out its minimum.
            let wait = max(0, minimumDuration - Date().timeIntervalSince(started))
            let finish = { [weak self] in
                guard let self, self.isRefreshing else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.isRefreshing = false }
            }
            if wait > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: finish) } else { finish() }
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

    var isOwnProfile: Bool { !userId.isEmpty && userId == AccountManager.shared.active?.id }

    func toggleMute() {
        let target = !isMuting
        isMuting = target
        let handle = user.formattedHandle
        let finish: (Result<Void, APIError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    if target { TimelineViewModel.shared.removeTweets(byAuthorId: self.userId, screenName: self.user.screenName) }
                    let key = target ? "post_muted_toast" : "profile_unmuted_toast"
                    AppToastManager.shared.show(LocalizationManager.shared.format(key, ["handle": handle]),
                                                icon: target ? "speaker.slash.fill" : "speaker.wave.2.fill")
                case .failure(let error):
                    self.isMuting = !target
                    EngagementGuard.reportFailure(error)
                }
            }
        }
        if target {
            APIClient.shared.muteUser(userId: userId, screenName: user.screenName, completion: finish)
        } else {
            APIClient.shared.unmuteUser(userId: userId, screenName: user.screenName, completion: finish)
        }
    }

    func toggleBlock() {
        let target = !isBlocking
        let wasFollowing = isFollowing
        isBlocking = target
        // Blocking someone also ends your follow of them
        if target { isFollowing = false }
        let handle = user.formattedHandle
        let finish: (Result<Void, APIError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    if target { TimelineViewModel.shared.removeTweets(byAuthorId: self.userId, screenName: self.user.screenName) }
                    let key = target ? "post_blocked_toast" : "profile_unblocked_toast"
                    AppToastManager.shared.show(LocalizationManager.shared.format(key, ["handle": handle]),
                                                icon: target ? "nosign" : "checkmark.circle")
                case .failure(let error):
                    self.isBlocking = !target
                    self.isFollowing = wasFollowing
                    EngagementGuard.reportFailure(error)
                }
            }
        }
        if target {
            APIClient.shared.blockUser(userId: userId, screenName: user.screenName, completion: finish)
        } else {
            APIClient.shared.unblockUser(userId: userId, screenName: user.screenName, completion: finish)
        }
    }

    // Fetched when the pointer reaches the menu, so most profile visits cost no extra request
    func loadOwnedListsIfNeeded() {
        guard ownedLists == nil, !isLoadingLists, !userId.isEmpty, let ownerId = AccountManager.shared.active?.id else { return }
        isLoadingLists = true
        APIClient.shared.fetchOwnedLists(ownerId: ownerId, targetUserId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingLists = false
                switch result {
                case .success(let lists):
                    self.ownedLists = lists
                    self.listsFailed = false
                case .failure(let error):
                    self.listsFailed = true
                }
            }
        }
    }

    func toggleList(_ list: OwnedList) {
        let target = !list.isMember
        setMember(target, of: list.id)
        let handle = user.formattedHandle
        APIClient.shared.setListMember(target, listId: list.id, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    let key = target ? "profile_added_to_list" : "profile_removed_from_list"
                    AppToastManager.shared.show(LocalizationManager.shared.format(key, ["handle": handle, "list": list.name]),
                                                icon: "list.bullet")
                case .failure(let error):
                    self.setMember(!target, of: list.id)
                    EngagementGuard.reportFailure(error)
                }
            }
        }
    }

    private func setMember(_ member: Bool, of listId: String) {
        guard let index = ownedLists?.firstIndex(where: { $0.id == listId }) else { return }
        ownedLists?[index].isMember = member
    }

    func toggleFollow() {
        guard !isFollowBusy, !userId.isEmpty else { return }
        if isBlockedByUser {
            AppToastManager.shared.show(
                LocalizationManager.shared.format("profile_blocked_follow", ["name": user.formattedHandle]),
                icon: "hand.raised.fill",
                duration: 3.6
            )
            return
        }
        let target = !isFollowing
        isFollowing = target
        isFollowBusy = true
        APIClient.shared.setFollowing(target, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFollowBusy = false
                if case .failure(let error) = result {
                    self.isFollowing = !target
                    EngagementGuard.reportFailure(error)
                }
            }
        }
    }
}
