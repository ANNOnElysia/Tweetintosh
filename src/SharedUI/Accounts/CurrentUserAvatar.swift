//
//  CurrentUserAvatar.swift
//  Tweetintosh
//
//  The signed-in account's own picture, shared by every composer and reply dock.
//

import SwiftUI

struct CurrentUserAvatar: View {
    var size: CGFloat
    @ObservedObject private var accounts = AccountManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if let url = accounts.active?.avatarUrl {
            CachedAsyncImage(urlString: url, targetSize: CGSize(width: size, height: size))
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
        } else {
            ZStack {
                Circle()
                    .fill(ThemeManager.accent.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundColor(ThemeManager.accent)
            }
        }
    }
}
