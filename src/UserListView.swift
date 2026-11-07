//
//  UserListView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  A full-pane page listing people: who liked or reposted a post (opened from "and 9 others liked your post"), or who an
//  account follows and is followed by (opened from the counts on a profile).
//

import SwiftUI

final class TweetUsersViewModel: ObservableObject {
    let kind: TweetUsersKind
    let tweetId: String

    @Published private(set) var users: [TweetUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    private var cursor: String?
    private var exhausted = false

    init(kind: TweetUsersKind, tweetId: String) {
        self.kind = kind
        self.tweetId = tweetId
    }

    func load(more: Bool = false) {
        guard !isLoading, !(more && (exhausted || cursor == nil)) else { return }
        isLoading = true
        failed = false
        APIClient.shared.fetchTweetUsers(kind: kind, tweetId: tweetId, cursor: more ? cursor : nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.hasLoaded = true
                switch result {
                case .success(let page):
                    let existing = Set(self.users.map { $0.id })
                    let fresh = page.users.filter { !existing.contains($0.id) }
                    self.users.append(contentsOf: fresh)
                    self.cursor = page.bottomCursor
                    if fresh.isEmpty || page.bottomCursor == nil { self.exhausted = true }
                case .failure:
                    self.failed = true
                }
            }
        }
    }
}

struct UserListView: View {
    let onDismiss: () -> Void
    @StateObject private var vm: TweetUsersViewModel
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    init(kind: TweetUsersKind, tweetId: String, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: TweetUsersViewModel(kind: kind, tweetId: tweetId))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()

            ScrollContainer(topSpacer: 58, onNearBottom: { vm.load(more: true) }) {
                if vm.users.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.users) { user in
                        userRow(user)
                    }
                    if vm.isLoading {
                        LoadingIndicator()
                            .padding(.vertical, 8)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .onAppear { vm.load() }
    }

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

            Text(loc.t(vm.kind.titleKey))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(ThemeManager.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @ViewBuilder private var emptyState: some View {
        Group {
            if vm.isLoading || !vm.hasLoaded {
                LoadingIndicator()
            } else if vm.failed {
                VStack(spacing: 10) {
                    Text(loc.t(vm.kind == .following || vm.kind == .followers ? "follow_list_load_failed" : "users_load_failed"))
                        .font(.system(size: 13.5))
                        .foregroundColor(ThemeManager.secondaryText)
                    Button(loc.t("profile_retry")) { vm.load() }
                }
            } else {
                Text(loc.t("users_empty"))
                    .font(.system(size: 13.5))
                    .foregroundColor(ThemeManager.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func userRow(_ user: TweetUser) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CachedAsyncImage(urlString: user.avatarUrl, targetSize: CGSize(width: 44, height: 44))
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                    .peekable(.profile(user))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                            .lineLimit(1)
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    Text(user.formattedHandle)
                        .font(.system(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 13))
                            .foregroundColor(ThemeManager.primaryText.opacity(0.85))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { NavigationManager.shared.openProfile(user) }

            Divider().background(ThemeManager.divider)
        }
    }
}
