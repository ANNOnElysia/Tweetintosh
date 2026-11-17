//
//  ArticleCardView.swift
//  Tweetintosh
//
//  The article card under a post, including the preview fetch for posts X didn't send one with.
//

import SwiftUI

// MARK: - Card shown under a post that has an article

struct ArticleCardView: View {
    let article: TweetArticle
    var isPlaceholder = false
    let onOpen: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                if let cover = article.coverUrl {
                    Color.clear
                        .aspectRatio(2.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(CachedAsyncImage(urlString: cover, placeholderColor: ThemeManager.cardBackground, targetSize: CGSize(width: 520, height: 260)))
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(loc.t("article_label"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(ThemeManager.accent)

                    if isPlaceholder {
                        // The title is on its way: a quiet bar in its place
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ThemeManager.secondaryText.opacity(0.18))
                            .frame(height: 14)
                            .frame(maxWidth: 220)
                            .padding(.vertical, 2)
                    } else {
                        Text(article.title)
                            .font(theme.appFont(size: 15, weight: .bold))
                            .foregroundColor(ThemeManager.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    if !article.previewText.isEmpty {
                        Text(article.previewText)
                            .font(theme.appFont(size: 12.5))
                            .foregroundColor(ThemeManager.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ThemeManager.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ThemeManager.border, lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.target)
    }
}

// MARK: - Posts whose article preview X didn't send

// Cached timelines and some list feeds carry the link to an article but not its preview. The title, opening lines and
// cover are then fetched when the post is shown, so the post still gets its card instead of a bare link.
final class ArticlePreviewStore: ObservableObject {
    static let shared = ArticlePreviewStore()
    @Published private(set) var previews: [String: TweetArticle] = [:]
    @Published private(set) var failed: Set<String> = []
    private var loading: Set<String> = []
    // A long session can show any number of article posts, and these cards are only a shortcut for the next visit.
    private static let maxEntries = 200
    private var previewOrder: [String] = []
    private var failedOrder: [String] = []

    func load(tweetId: String) {
        guard previews[tweetId] == nil, !failed.contains(tweetId), !loading.contains(tweetId) else { return }
        loading.insert(tweetId)
        APIClient.shared.fetchArticle(tweetId: tweetId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading.remove(tweetId)
                switch result {
                case .success(let document):
                    let opening = document.blocks.lazy.map(\.plainText).first { !$0.isEmpty } ?? ""
                    if self.previews[tweetId] == nil { self.previewOrder.append(tweetId) }
                    self.previews[tweetId] = TweetArticle(id: tweetId, title: document.title, previewText: opening, coverUrl: document.coverUrl)
                    if self.previewOrder.count > Self.maxEntries {
                        self.previews[self.previewOrder.removeFirst()] = nil
                    }
                case .failure:
                    if self.failed.insert(tweetId).inserted { self.failedOrder.append(tweetId) }
                    if self.failedOrder.count > Self.maxEntries {
                        self.failed.remove(self.failedOrder.removeFirst())
                    }
                }
            }
        }
    }
}

// The card shown under a post that has an article, with its preview from X or, failing that, fetched here
struct TweetArticleCard: View {
    let tweet: Tweet
    @ObservedObject private var store = ArticlePreviewStore.shared

    private var preview: TweetArticle? { tweet.article ?? store.previews[tweet.id] }

    var body: some View {
        Group {
            if let preview = preview {
                ArticleCardView(article: preview) {
                    var opened = tweet
                    opened.article = preview
                    NavigationManager.shared.openArticle(for: opened)
                }
            } else {
                ArticleCardView(article: TweetArticle(id: tweet.id, title: "", previewText: "", coverUrl: nil), isPlaceholder: true) {
                    var opened = tweet
                    opened.article = TweetArticle(id: tweet.id, title: "", previewText: "", coverUrl: nil)
                    NavigationManager.shared.openArticle(for: opened)
                }
            }
        }
        .onAppear { if tweet.article == nil { store.load(tweetId: tweet.id) } }
        // A reused table cell keeps this view and hands it another post, so onAppear doesn't run again
        .onChange(of: tweet.id) { if tweet.article == nil { store.load(tweetId: tweet.id) } }
    }
}
