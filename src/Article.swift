//
//  Article.swift
//  Tweetintosh - Headless Data-driven Client
//
//  X Articles: long posts written in a rich-text editor. X sends them as Draft.js content (typed blocks with
//  inline styles and entities) and embeds tables and other markdown as MARKDOWN entities. This file turns that into
//  blocks the reader page can draw, with no web page involved.
//

import Foundation
import SwiftUI

// MARK: - Document

struct ArticleDocument {
    var title: String
    var coverUrl: String?
    var author: TweetUser?
    var publishedAt: Date?
    var blocks: [ArticleBlock]

    // Minutes to read, counting a Chinese/Japanese/Korean character as a word-equivalent at a slower pace
    var readingMinutes: Int {
        var cjk = 0, other = 0
        for block in blocks {
            let text = block.plainText
            for scalar in text.unicodeScalars {
                if (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value) {
                    cjk += 1
                }
            }
            other += text.split { $0.isWhitespace }.count
        }
        let minutes = Double(cjk) / 450.0 + Double(other) / 230.0
        return max(1, Int(minutes.rounded()))
    }
}

enum ArticleBlock {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case quote(AttributedString)
    case listItem(ordered: Bool, number: Int, AttributedString)
    case code(String)
    case image(url: URL, aspect: CGFloat?, caption: String?)
    case divider
    case markdown([MarkdownBlock])
    case embeddedPost(id: String)

    var plainText: String {
        switch self {
        case .paragraph(let t), .quote(let t), .heading(_, let t), .listItem(_, _, let t): return String(t.characters)
        case .code(let s): return s
        case .markdown(let blocks): return blocks.map(\.plainText).joined(separator: " ")
        default: return ""
        }
    }
}

// MARK: - Draft.js content

enum ArticleParser {
    // The article of the post `tweetId` inside a TweetDetail answer
    static func parse(detailJSON json: [String: Any], tweetId: String) -> ArticleDocument? {
        var tweetObject: [String: Any]?
        func find(_ node: Any) {
            guard tweetObject == nil else { return }
            if let dict = node as? [String: Any] {
                if (dict["rest_id"] as? String) == tweetId, dict["article"] != nil { tweetObject = dict; return }
                for value in dict.values { find(value) }
            } else if let array = node as? [Any] {
                for value in array { find(value) }
            }
        }
        find(json)
        guard let tweet = tweetObject,
              let entity = ((tweet["article"] as? [String: Any])?["article_results"] as? [String: Any])?["result"] as? [String: Any],
              let title = entity["title"] as? String else { return nil }

        let cover = ((entity["cover_media"] as? [String: Any])?["media_info"] as? [String: Any])?["original_img_url"] as? String
        var author: TweetUser?
        if let userResult = ((tweet["core"] as? [String: Any])?["user_results"] as? [String: Any])?["result"] as? [String: Any] {
            author = APIClient.parseUser(userResult)
        }
        var published: Date?
        if let seconds = (entity["metadata"] as? [String: Any])?["first_published_at_secs"] as? Double {
            published = Date(timeIntervalSince1970: seconds)
        }

        // Pictures inside the text are listed separately and referred to by media id
        var media: [String: (url: String, aspect: CGFloat?)] = [:]
        for item in (entity["media_entities"] as? [[String: Any]]) ?? [] {
            guard let id = (item["media_id"] as? String) ?? (item["media_id"] as? NSNumber)?.stringValue,
                  let info = item["media_info"] as? [String: Any],
                  let url = info["original_img_url"] as? String else { continue }
            var aspect: CGFloat?
            if let w = info["original_img_width"] as? Double, let h = info["original_img_height"] as? Double, h > 0 { aspect = CGFloat(w / h) }
            media[id] = (url, aspect)
        }

        var blocks: [ArticleBlock] = []
        if let content = entity["content_state"] as? [String: Any] {
            blocks = convert(content: content, media: media)
        } else if let plain = entity["plain_text"] as? String {
            blocks = plain.components(separatedBy: "\n\n").map { .paragraph(AttributedString($0)) }
        } else if let preview = entity["preview_text"] as? String {
            blocks = [.paragraph(AttributedString(preview))]
        }
        return ArticleDocument(title: title, coverUrl: cover, author: author, publishedAt: published, blocks: blocks)
    }

    private static func convert(content: [String: Any], media: [String: (url: String, aspect: CGFloat?)]) -> [ArticleBlock] {
        // entityMap is a list of {key, value} in X's answers (a dictionary in plain Draft.js)
        var entities: [String: [String: Any]] = [:]
        if let list = content["entityMap"] as? [[String: Any]] {
            for item in list {
                if let key = (item["key"] as? String) ?? (item["key"] as? NSNumber)?.stringValue, let value = item["value"] as? [String: Any] {
                    entities[key] = value
                }
            }
        } else if let dict = content["entityMap"] as? [String: [String: Any]] {
            entities = dict
        }

        var out: [ArticleBlock] = []
        var orderedNumber = 0
        for raw in (content["blocks"] as? [[String: Any]]) ?? [] {
            let type = (raw["type"] as? String) ?? "unstyled"
            let text = (raw["text"] as? String) ?? ""
            let styles = (raw["inlineStyleRanges"] as? [[String: Any]]) ?? []
            let ranges = (raw["entityRanges"] as? [[String: Any]]) ?? []
            let mentions = ((raw["data"] as? [String: Any])?["mentions"] as? [[String: Any]]) ?? []

            if type != "ordered-list-item" { orderedNumber = 0 }

            switch type {
            case "atomic":
                // An atomic block is a single embedded thing, named by its entity
                guard let key = ranges.first.flatMap({ ($0["key"] as? Int).map(String.init) ?? ($0["key"] as? String) }),
                      let entity = entities[key] else { continue }
                if let block = atomicBlock(entity: entity, media: media) { out.append(block) }
            case "header-one", "header-two", "header-three", "header-four":
                let level = ["header-one": 1, "header-two": 2, "header-three": 3, "header-four": 4][type] ?? 2
                out.append(.heading(level: level, styled(text, styles: styles, ranges: ranges, entities: entities, mentions: mentions)))
            case "blockquote":
                out.append(.quote(styled(text, styles: styles, ranges: ranges, entities: entities, mentions: mentions)))
            case "unordered-list-item":
                out.append(.listItem(ordered: false, number: 0, styled(text, styles: styles, ranges: ranges, entities: entities, mentions: mentions)))
            case "ordered-list-item":
                orderedNumber += 1
                out.append(.listItem(ordered: true, number: orderedNumber, styled(text, styles: styles, ranges: ranges, entities: entities, mentions: mentions)))
            case "code-block":
                out.append(.code(text))
            default:
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                out.append(.paragraph(styled(text, styles: styles, ranges: ranges, entities: entities, mentions: mentions)))
            }
        }
        return out
    }

    private static func atomicBlock(entity: [String: Any], media: [String: (url: String, aspect: CGFloat?)]) -> ArticleBlock? {
        let type = (entity["type"] as? String) ?? ""
        let data = (entity["data"] as? [String: Any]) ?? [:]
        switch type {
        case "MARKDOWN":
            guard let markdown = data["markdown"] as? String else { return nil }
            return .markdown(MarkdownParser.parse(markdown))
        case "MEDIA":
            let items = (data["mediaItems"] as? [[String: Any]]) ?? []
            for item in items {
                let id = (item["mediaId"] as? String) ?? (item["mediaId"] as? NSNumber)?.stringValue ?? (item["media_id"] as? String)
                if let id = id, let found = media[id], let url = URL(string: found.url) {
                    return .image(url: url, aspect: found.aspect, caption: data["caption"] as? String)
                }
            }
            return nil
        case "DIVIDER":
            return .divider
        case "TWEET":
            guard let id = (data["tweetId"] as? String) ?? (data["tweetId"] as? NSNumber)?.stringValue else { return nil }
            return .embeddedPost(id: id)
        default:
            return nil
        }
    }

    // Draft.js ranges count UTF-16 units, like NSString
    private static func styled(_ text: String, styles: [[String: Any]], ranges: [[String: Any]],
                               entities: [String: [String: Any]], mentions: [[String: Any]]) -> AttributedString {
        var out = AttributedString(text)
        func apply(_ offset: Int?, _ length: Int?, _ change: (inout AttributedSubstring) -> Void) {
            guard let offset = offset, let length = length, length > 0,
                  let range = Range(NSRange(location: offset, length: length), in: text),
                  let attrRange = Range(range, in: out) else { return }
            change(&out[attrRange])
        }
        for style in styles {
            let name = (style["style"] as? String) ?? ""
            apply(style["offset"] as? Int, style["length"] as? Int) { run in
                switch name.lowercased() {
                case "bold": run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                case "italic": run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.emphasized)
                case "code": run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.code)
                case "strikethrough": run.strikethroughStyle = .single
                case "underline": run.underlineStyle = .single
                default: break
                }
            }
        }
        for range in ranges {
            let key = (range["key"] as? Int).map(String.init) ?? (range["key"] as? String) ?? ""
            guard let entity = entities[key], (entity["type"] as? String) == "LINK",
                  let url = ((entity["data"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:)) else { continue }
            apply(range["offset"] as? Int, range["length"] as? Int) { run in
                run.link = url
                run.foregroundColor = ThemeManager.accent
            }
        }
        for mention in mentions {
            guard let from = mention["fromIndex"] as? Int, let to = mention["toIndex"] as? Int, let name = mention["text"] as? String,
                  let url = URL(string: "tweetintosh://profile/\(name)") else { continue }
            apply(from, to - from) { run in
                run.link = url
                run.foregroundColor = ThemeManager.accent
            }
        }
        return out
    }
}

// MARK: - Markdown

indirect enum MarkdownBlock {
    case heading(level: Int, AttributedString)
    case paragraph(AttributedString)
    case quote([MarkdownBlock])
    case bullets([AttributedString])
    case numbers([AttributedString])
    case code(language: String?, String)
    case table(header: [AttributedString], rows: [[AttributedString]], alignments: [Alignment])
    case rule

    var plainText: String {
        switch self {
        case .heading(_, let t), .paragraph(let t): return String(t.characters)
        case .quote(let blocks): return blocks.map(\.plainText).joined(separator: " ")
        case .bullets(let items), .numbers(let items): return items.map { String($0.characters) }.joined(separator: " ")
        case .code(_, let s): return s
        case .table(let header, let rows, _): return (header + rows.flatMap { $0 }).map { String($0.characters) }.joined(separator: " ")
        case .rule: return ""
        }
    }
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        func inline(_ text: String) -> AttributedString {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            var parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
            for run in parsed.runs where run.link != nil {
                parsed[run.range].foregroundColor = ThemeManager.accent
            }
            return parsed
        }
        func isRule(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.count >= 3 && (t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" } || t.allSatisfy { $0 == "_" })
        }
        func isTableSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("-"), t.contains("|") || t.hasPrefix(":") else { return false }
            return t.allSatisfy { "|-: ".contains($0) }
        }
        func cells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            // Split on pipes that are not escaped
            var out: [String] = [], current = ""
            var escaped = false
            for ch in t {
                if escaped { current.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; current.append(ch); continue }
                if ch == "|" { out.append(current.trimmingCharacters(in: .whitespaces)); current = "" } else { current.append(ch) }
            }
            out.append(current.trimmingCharacters(in: .whitespaces))
            return out
        }
        func startsList(_ line: String) -> (ordered: Bool, text: String)? {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let first = t.first, "-*+".contains(first), t.dropFirst().first == " " { return (false, String(t.dropFirst(2))) }
            if let dot = t.firstIndex(of: "."), dot != t.startIndex, t[t.startIndex..<dot].allSatisfy({ $0.isNumber }),
               t[t.index(after: dot)...].first == " " { return (true, String(t[t.index(dot, offsetBy: 2)...])) }
            return nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }

            // Fenced code
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[index]); index += 1
                }
                index += 1
                blocks.append(.code(language: language.isEmpty ? nil : language, body.joined(separator: "\n")))
                continue
            }
            // Heading
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                if level <= 6, trimmed.dropFirst(level).first == " " {
                    blocks.append(.heading(level: level, inline(String(trimmed.dropFirst(level + 1)))))
                    index += 1
                    continue
                }
            }
            if isRule(trimmed) { blocks.append(.rule); index += 1; continue }
            // Table: a row of cells followed by the separator row
            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                let header = cells(line)
                let alignments: [Alignment] = cells(lines[index + 1]).map { spec in
                    let left = spec.hasPrefix(":"), right = spec.hasSuffix(":")
                    return left && right ? .center : (right ? .trailing : .leading)
                }
                index += 2
                var rows: [[AttributedString]] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    var row = cells(lines[index]).map(inline)
                    while row.count < header.count { row.append(AttributedString("")) }
                    rows.append(Array(row.prefix(header.count)))
                    index += 1
                }
                blocks.append(.table(header: header.map(inline), rows: rows, alignments: alignments))
                continue
            }
            // Quote
            if trimmed.hasPrefix(">") {
                var inner: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var t = lines[index].trimmingCharacters(in: .whitespaces)
                    t.removeFirst()
                    if t.hasPrefix(" ") { t.removeFirst() }
                    inner.append(t); index += 1
                }
                blocks.append(.quote(parse(inner.joined(separator: "\n"))))
                continue
            }
            // Lists
            if let first = startsList(line) {
                var items: [AttributedString] = [inline(first.text)]
                index += 1
                while index < lines.count, let next = startsList(lines[index]), next.ordered == first.ordered {
                    items.append(inline(next.text)); index += 1
                }
                blocks.append(first.ordered ? .numbers(items) : .bullets(items))
                continue
            }
            // Paragraph: lines up to the next blank line or block start
            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("```") || next.hasPrefix("#") || next.hasPrefix(">") || startsList(lines[index]) != nil || isRule(next) { break }
                if next.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) { break }
                paragraph.append(next); index += 1
            }
            blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
        }
        return blocks
    }
}

// MARK: - Fetching

extension APIClient {
    // The full article of a post: X's TweetDetail with the toggle that includes the article's rich content
    func fetchArticle(tweetId: String, completion: @escaping (Result<ArticleDocument, APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        let features: [String: Any] = [
            "rweb_video_screen_enabled": true, "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": false, "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true, "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "articles_preview_enabled": true, "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true, "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true, "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false, "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reached_appeal_enabled": true, "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "rweb_tipjar_consumption_enabled": true, "responsive_web_enhance_cards_enabled": false
        ]
        let variables: [String: Any] = [
            "focalTweetId": tweetId, "with_rux_injections": false, "rankingMode": "Relevance", "includePromotedContent": false,
            "withCommunity": true, "withQuickPromoteEligibility": false, "withBirdwatchNotes": true, "withVoice": true
        ]
        let toggles: [String: Any] = ["withArticleRichContentState": true, "withArticlePlainText": false]
        func encode(_ object: [String: Any]) -> String? {
            (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
        }
        guard let vars = encode(variables), let feats = encode(features), let tog = encode(toggles) else {
            completion(.failure(.parseError)); return
        }
        var comps = URLComponents(string: "https://x.com/i/api/graphql/gJoREC4Bspo4kJ0ax9C3sQ/TweetDetail")!
        comps.queryItems = [URLQueryItem(name: "variables", value: vars), URLQueryItem(name: "features", value: feats),
                            URLQueryItem(name: "fieldToggles", value: tog)]
        guard let url = comps.url else { completion(.failure(.invalidResponse)); return }
        var request = URLRequest(url: url)
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://x.com/", forHTTPHeaderField: "referer")
        session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(.networkError(error))); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.serverError("HTTP \(status)")))
                return
            }
            if let document = ArticleParser.parse(detailJSON: json, tweetId: tweetId) {
                completion(.success(document))
            } else {
                completion(.failure(.parseError))
            }
        }.resume()
    }
}
