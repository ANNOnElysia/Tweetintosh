//
//  ArticleReaderModel.swift
//  Tweetintosh
//
//  Loads one article document for the reader.
//

import SwiftUI

final class ArticleViewModel: ObservableObject {
    let tweet: Tweet
    @Published private(set) var document: ArticleDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false

    init(tweet: Tweet) { self.tweet = tweet }

    func load() {
        guard !isLoading, document == nil else { return }
        isLoading = true
        failed = false
        APIClient.shared.fetchArticle(tweetId: tweet.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let document): self.document = document
                case .failure: self.failed = true
                }
            }
        }
    }
}
