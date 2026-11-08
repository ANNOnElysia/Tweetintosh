//
//  LinkCardPreview.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The link card shown in the post and reply composers while a post holds a link, as X's own composer does. The
//  preview is X's: the same query its web client sends, so what is shown is the card the post will get. Closing
//  it posts with X's "tombstone" card, which is how X's web client publishes a link without its card.
//

import SwiftUI
import AppKit

struct LinkCardPreview: Equatable {
    let link: String
    let title: String
    let domain: String
    let imageURL: String?
    // summary_large_image: a wide picture above the title, rather than a square one beside it
    let isLarge: Bool
}

extension APIClient {
    /// Asks X for the card a post holding `link` would get, with the query X's own composer uses. `nil` when X has no
    /// card for it.
    func fetchLinkCardPreview(for link: String, attempt: Int = 0, completion: @escaping (LinkCardPreview?) -> Void) {
        graphQLGet(operation: "composerCardPreviewQuery", variables: ["url": link]) { [weak self] result in
            guard case .success(let json) = result else { return completion(nil) }
            let found = (json["data"] as? [String: Any])?["card_by_card_uri"] as? [String: Any]
            if let card = found?["legacy"] as? [String: Any] {
                return completion(Self.parseLinkCard(card, link: link))
            }
            // A link X has not seen before comes back as a bare card while X fetches the page, and the card follows a
            // few seconds later, so ask again a few times before giving up
            guard found != nil, attempt < 4, let self = self else { return completion(nil) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
                self.fetchLinkCardPreview(for: link, attempt: attempt + 1, completion: completion)
            }
        }
    }

    private static func parseLinkCard(_ card: [String: Any], link: String) -> LinkCardPreview? {
        // Binding values come as a key/value array, or keyed by name from X's older card service
        var values: [String: [String: Any]] = [:]
        if let dict = card["binding_values"] as? [String: [String: Any]] {
            values = dict
        } else if let list = card["binding_values"] as? [[String: Any]] {
            for item in list {
                if let key = item["key"] as? String, let value = item["value"] as? [String: Any] { values[key] = value }
            }
        }
        func string(_ key: String) -> String? {
            (values[key]?["string_value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func image(_ keys: [String]) -> String? {
            for key in keys {
                if let url = (values[key]?["image_value"] as? [String: Any])?["url"] as? String { return url }
            }
            return nil
        }
        guard let title = string("title") else { return nil }
        let isLarge = (card["name"] as? String)?.contains("large_image") == true
        let picture = isLarge
            ? image(["summary_photo_image_large", "summary_photo_image", "thumbnail_image_large", "thumbnail_image"])
            : image(["thumbnail_image_large", "thumbnail_image", "summary_photo_image"])
        let domain = string("vanity_url") ?? string("domain") ?? URL(string: link)?.host ?? link
        return LinkCardPreview(link: link, title: title, domain: domain, imageURL: picture, isLarge: isLarge && picture != nil)
    }
}

/// Follows a composer's text and holds the card for the last link in it, which is the one X turns into the card.
final class LinkCardPreviewModel: ObservableObject {
    @Published private(set) var preview: LinkCardPreview?
    // The link whose card was closed; a different link brings a card back, as in X's composer
    @Published private(set) var dismissedLink: String?
    private var currentLink: String?
    private var pending: DispatchWorkItem?

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func lastLink(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.matches(in: text, range: range).last(where: {
            guard let scheme = $0.url?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }) else { return nil }
        return match.url?.absoluteString
    }

    /// Whether the post should go out without its card: the link in it now is the one whose card was closed.
    func cardIsDismissed(for text: String) -> Bool {
        guard let link = Self.lastLink(in: text) else { return false }
        return link == dismissedLink
    }

    func textChanged(_ text: String) {
        let link = Self.lastLink(in: text)
        guard link != currentLink else { return }
        currentLink = link
        pending?.cancel()
        if preview?.link != link { preview = nil }
        guard let link = link, link != dismissedLink else { return }
        // Wait for typing to pause, so a link being typed is not looked up one letter at a time
        let work = DispatchWorkItem { [weak self] in
            APIClient.shared.fetchLinkCardPreview(for: link) { card in
                DispatchQueue.main.async {
                    guard let self = self, self.currentLink == link, self.dismissedLink != link else { return }
                    withAnimation(.easeOut(duration: 0.2)) { self.preview = card }
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func dismiss() {
        dismissedLink = preview?.link ?? currentLink
        withAnimation(.easeOut(duration: 0.2)) { preview = nil }
    }
}

struct LinkCardPreviewView: View {
    let card: LinkCardPreview
    var isDisabled = false
    let onDismiss: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    private static let compactHeight: CGFloat = 104

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeManager.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ThemeManager.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.75)))
                }
                .buttonStyle(.target)
                .padding(8)
                .disabled(isDisabled)
                .help(loc.t("remove_link_preview"))
                .accessibilityLabel(loc.t("remove_link_preview"))
            }
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if card.isLarge {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(1.91, contentMode: .fit)
                    .overlay(CachedAsyncImage(urlString: card.imageURL, placeholderColor: ThemeManager.divider))
                    .clipped()
                labels
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        } else {
            HStack(spacing: 0) {
                if card.imageURL != nil {
                    CachedAsyncImage(urlString: card.imageURL, placeholderColor: ThemeManager.divider,
                                     targetSize: CGSize(width: Self.compactHeight, height: Self.compactHeight))
                        .frame(width: Self.compactHeight, height: Self.compactHeight)
                        .clipped()
                    Rectangle().fill(ThemeManager.border).frame(width: 1)
                }
                labels
                    .padding(.leading, 14)
                    .padding(.trailing, 40)   // clear of the close button
            }
            .frame(height: Self.compactHeight)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(theme.appFont(size: 14, weight: .medium))
                .foregroundColor(ThemeManager.primaryText)
                .lineLimit(2)
            Text(card.domain)
                .font(theme.appFont(size: 13))
                .foregroundColor(ThemeManager.secondaryText)
                .lineLimit(1)
        }
    }

    /// The room the card takes in a composer of the given width, for the sheets that size themselves.
    static func height(for card: LinkCardPreview?, width: CGFloat) -> CGFloat {
        guard let card = card else { return 0 }
        return card.isLarge ? width / 1.91 + 64 : compactHeight + 12
    }
}
