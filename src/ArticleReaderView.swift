//
//  ArticleReaderView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The page that reads an X Article: cover, title, author and the text, drawn natively (headings, quotes, lists,
//  code, tables, pictures). No web page is involved.
//

import SwiftUI
import os

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
        .buttonStyle(.plain)
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
                    self.previews[tweetId] = TweetArticle(id: tweetId, title: document.title, previewText: opening, coverUrl: document.coverUrl)
                case .failure:
                    self.failed.insert(tweetId)
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

// MARK: - Reader

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

struct ArticleReaderView: View {
    let onDismiss: () -> Void
    @StateObject private var vm: ArticleViewModel
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    private static let columnWidth: CGFloat = 680

    init(tweet: Tweet, onDismiss: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: ArticleViewModel(tweet: tweet))
        self.onDismiss = onDismiss
    }

    private var title: String { vm.document?.title ?? vm.tweet.article?.title ?? "" }
    private var coverUrl: String? { vm.document?.coverUrl ?? vm.tweet.article?.coverUrl }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()

            ScrollContainer(topSpacer: 58) {
                header
                if let document = vm.document {
                    ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                        row { blockView(block) }
                    }
                    Color.clear.frame(height: 80)
                } else if vm.failed {
                    row {
                        VStack(spacing: 10) {
                            Text(loc.t("article_load_failed"))
                                .font(.system(size: 13.5))
                                .foregroundColor(ThemeManager.secondaryText)
                                .multilineTextAlignment(.center)
                            Button(loc.t("profile_retry")) { vm.load() }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    row {
                        LoadingIndicator()
                            .padding(.vertical, 50)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .onAppear { vm.load() }
    }

    // Every piece sits in a centred column of comfortable reading width
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: Self.columnWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
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

            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(ThemeManager.accent)
                Text(loc.t("article_label"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(ThemeManager.primaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: Header: cover, title, author

    @ViewBuilder private var header: some View {
        if let cover = coverUrl {
            row {
                // The box sets the size; the picture fills it and is cut to it (a picture sized on its own overflows)
                Color.clear
                    .aspectRatio(16.0 / 8.5, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(CachedAsyncImage(urlString: cover, placeholderColor: ThemeManager.cardBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ThemeManager.border, lineWidth: 0.6))
                    .padding(.top, 6)
            }
        }
        row {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(theme.appFont(size: 34, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                authorLine

                Rectangle()
                    .fill(ThemeManager.divider)
                    .frame(height: 1)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
        }
    }

    private var authorLine: some View {
        let author = vm.document?.author ?? vm.tweet.author
        let date = vm.document?.publishedAt ?? vm.tweet.createdAt
        return HStack(spacing: 11) {
            CachedAsyncImage(urlString: author.avatarUrl, targetSize: CGSize(width: 38, height: 38))
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                .opensProfile(author)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(author.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    if author.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeManager.accent)
                    }
                }
                HStack(spacing: 5) {
                    Text(author.formattedHandle)
                    Text("·")
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                    if let minutes = vm.document?.readingMinutes {
                        Text("·")
                        Text(loc.format("article_read_time", ["minutes": "\(minutes)"]))
                    }
                }
                .font(.system(size: 12.5))
                .foregroundColor(ThemeManager.secondaryText)
                .lineLimit(1)
            }
            .opensProfile(author)
            Spacer(minLength: 0)
        }
    }

    // MARK: Body blocks

    private func bodyFont(_ size: CGFloat) -> Font { theme.tweetFont(size: size) }

    @ViewBuilder private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .handlesTweetLinks()
                .font(bodyFont(17))
                .foregroundColor(ThemeManager.primaryText.opacity(theme.isLight ? 0.92 : 0.9))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 8)
        case .heading(let level, let text):
            Text(text)
                .handlesTweetLinks()
                .font(theme.appFont(size: level == 1 ? 27 : (level == 2 ? 22 : 19), weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 30 : 22)
                .padding(.bottom, 6)
        case .quote(let text):
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ThemeManager.accent.opacity(0.7))
                    .frame(width: 3)
                Text(text)
                    .handlesTweetLinks()
                    .font(bodyFont(16.5))
                    .foregroundColor(ThemeManager.secondaryText)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
        case .listItem(let ordered, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ordered ? "\(number)." : "•")
                    .font(bodyFont(16.5))
                    .foregroundColor(ThemeManager.accent)
                    .frame(width: ordered ? 26 : 14, alignment: .trailing)
                Text(text)
                    .handlesTweetLinks()
                    .font(bodyFont(17))
                    .foregroundColor(ThemeManager.primaryText.opacity(theme.isLight ? 0.92 : 0.9))
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, 6)
            .padding(.vertical, 3)
        case .code(let code):
            codeBox(code)
        case .image(let url, let aspect, let caption):
            VStack(spacing: 8) {
                Color.clear
                    .aspectRatio(aspect ?? 1.6, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(CachedAsyncImage(urlString: url.absoluteString, placeholderColor: ThemeManager.cardBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let caption = caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 12)
        case .divider:
            Rectangle()
                .fill(ThemeManager.divider)
                .frame(height: 1)
                .padding(.vertical, 22)
        case .markdown(let blocks):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, md in
                    MarkdownBlockView(block: md)
                }
            }
            .padding(.vertical, 6)
        case .embeddedPost(let id):
            Button {
                let stub = Tweet(id: id, text: "", createdAt: Date(), author: vm.tweet.author, media: [],
                                 replyCount: 0, retweetCount: 0, favoriteCount: 0, isRetweet: false, retweetedBy: nil)
                NavigationManager.shared.openTweetDetail(stub)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                    Text(loc.t("article_embedded_post"))
                        .font(.system(size: 13.5, weight: .medium))
                }
                .foregroundColor(ThemeManager.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ThemeManager.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ThemeManager.border, lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
    }

    private func codeBox(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(ThemeManager.primaryText.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize()
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.isLight ? Color.black.opacity(0.045) : Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 8)
    }
}

// MARK: - Markdown blocks

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .handlesTweetLinks()
                .font(theme.appFont(size: level == 1 ? 24 : (level == 2 ? 20 : 17.5), weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 16)
                .padding(.bottom, 4)
        case .paragraph(let text):
            Text(text)
                .handlesTweetLinks()
                .font(theme.tweetFont(size: 16.5))
                .foregroundColor(ThemeManager.primaryText.opacity(0.9))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(ThemeManager.accent.opacity(0.7)).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in MarkdownBlockView(block: inner) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundColor(ThemeManager.accent).frame(width: 14, alignment: .trailing)
                        Text(item).handlesTweetLinks().lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .font(theme.tweetFont(size: 16.5))
                    .foregroundColor(ThemeManager.primaryText.opacity(0.9))
                }
            }
            .padding(.leading, 6).padding(.vertical, 6)
        case .numbers(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).").foregroundColor(ThemeManager.accent).frame(width: 26, alignment: .trailing)
                        Text(item).handlesTweetLinks().lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .font(theme.tweetFont(size: 16.5))
                    .foregroundColor(ThemeManager.primaryText.opacity(0.9))
                }
            }
            .padding(.leading, 6).padding(.vertical, 6)
        case .code(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(ThemeManager.primaryText.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.isLight ? Color.black.opacity(0.045) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.vertical, 6)
        case .rule:
            Rectangle().fill(ThemeManager.divider).frame(height: 1).padding(.vertical, 16)
        case .table(let header, let rows, let alignments):
            tableView(header: header, rows: rows, alignments: alignments)
                .padding(.vertical, 8)
        }
    }

    // A table whose columns share the width when they fit and scroll sideways when they don't
    private func tableView(header: [AttributedString], rows: [[AttributedString]], alignments: [Alignment]) -> some View {
        // Each column gets a definite width from its longest cell (a wide character counts double), so wrapped
        // cells measure their real height and rows never overlap
        let widths: [CGFloat] = header.indices.map { column in
            let cells = [header[column]] + rows.map { $0[column] }
            let units = cells.map { cell -> CGFloat in
                String(cell.characters).reduce(0) { $0 + ($1.unicodeScalars.first.map { $0.value > 0x2E80 } ?? false ? 2.0 : 1.0) }
            }.max() ?? 0
            return min(max(units * 7.6 + 26, 96), 300)
        }
        func cell(_ text: AttributedString, column: Int, isHeader: Bool) -> some View {
            let alignment = column < alignments.count ? alignments[column] : .leading
            return Text(text)
                .handlesTweetLinks()
                .font(.system(size: 14, weight: isHeader ? .semibold : .regular))
                .foregroundColor(isHeader ? ThemeManager.primaryText : ThemeManager.primaryText.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .multilineTextAlignment(alignment == .trailing ? .trailing : (alignment == .center ? .center : .leading))
                .frame(width: widths[column] - 24, alignment: alignment)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { column, text in
                        cell(text, column: column, isHeader: true)
                    }
                }
                .background(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, text in
                            cell(text, column: column, isHeader: false)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ThemeManager.border, lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
