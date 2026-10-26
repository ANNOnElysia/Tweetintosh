//
//  ProfileAPI.swift
//  Tweetintosh - Headless Data-driven Client
//
//  User profiles: profile lookup, the Posts / Replies / Media timelines, and follow / unfollow.
//

import Foundation
import os

private let graphQLLog = Logger(subsystem: "com.anno.tweetintosh", category: "graphql")

// MARK: - Models

struct UserProfile {
    var user: TweetUser
    var websiteUrl: URL?
    var websiteDisplay: String?
    var joinedAt: Date?
    var postsCount: Int?
    var isFollowing: Bool
    var isProtected: Bool
}

// A post in a profile tab; Replies-tab posts can be part of a conversation thread drawn with a connecting line
struct ProfileTimelineItem: Identifiable {
    let id: String
    var tweet: Tweet
    let threadAbove: Bool
    let threadBelow: Bool
}

enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    case media
    case replies

    var id: String { rawValue }
    
    // ⌥1 / ⌥2 / ⌥3: the profile tabs are the first menu on the page, so they take the number keys
    var shortcutKey: String {
        switch self {
        case .posts: return "⌥1"
        case .media: return "⌥2"
        case .replies: return "⌥3"
        }
    }
    
    static func forKeyCode(_ keyCode: UInt16) -> ProfileTab? {
        switch keyCode {
        case 18: return .posts
        case 19: return .media
        case 20: return .replies
        default: return nil
        }
    }
    
    var operationName: String {
        switch self {
        case .posts: return "UserTweets"
        case .replies: return "UserRepliesTimeline"
        case .media: return "UserMedia"
        }
    }
}

// MARK: - GraphQL Operation IDs

// X's web client addresses GraphQL operations by query IDs that change from time to time. Each operation
// has a few known IDs; the first that answers is remembered. If none work, the IDs are discovered from
// X's own signed-in web client.
final class GraphQLOperationIDs {
    static let shared = GraphQLOperationIDs()

    private let candidates: [String: [String]] = [
        "UserByScreenName": [
            "x3RLKWW1Tl7JgU7YtGxuzw", "AMIBMjtxEEATh4z8V9GtRg","32pL5BWe9WKeSK1MoPvFQQ", "1VOOyvKkiI3FMmkeDNxM9A",
            "xmU6X_CKVnQ5lSrCbAmJsg", "G3KGOASz96M-Qu0nwmGXNg", "qW5u-DAuXpMEG0zA1F7UGQ"
        ],
        "UserTweets": [
            "q6xj5bs0hapm9309hexA_g", "YHYMZsaMvzJvb5D2UVVjgw","Y9WM4Id6UcGFE8Z-hbnixw", "E3opETHurmVJflFsUBVuUQ",
            "V7H0Ap3_Hh2FyS75OCDO3Q", "HuTx74BxAnezK1gWvYY7zg", "eS7LO5Jy3xgmd3dbL044EA"
        ],
        "SearchTimeline": [
            "gkjsKepM6gl_HmFWoWKfgg", "UN1i3zUiCWa-6r-Uaho4fw", "Aj1nGkALq99Xg3XI0OZBtw",
            "flaR-PUMshxFWZWPNpq4zA", "U3QTLwGF8sZCHDuWIMSAmg"
        ],
        // Replaced the older UserTweetsAndReplies operation, which X no longer serves
        "UserRepliesTimeline": [
            "RFZCQszlYjo2RQYM-4vrTQ"
        ],
        // Who liked / reposted a post. No ids are known up front: they are read from X's web client on first use.
        "Favoriters": ["mDc_nU8xGv0cLRWtTaIEug"],
        "Retweeters": [],
        "UserMedia": [
            "eF8kYZ4r9zFLqcYno3I17A", "oMVVrI5kt3kOpyHHTTKf5Q","BGmkmGDG0kZPM-aoQtNTTw", "dexO_2tohK86JDudXXG3Yw",
            "MOLbHrtk8Ovu7DUNOLcXiA", "Le6KlbilFmSu-5VltFND-Q"
        ]
    ]

    private let defaultsKey = "Tweetintosh_GraphQLOperationIDs"
    private let lock = NSLock()
    private var working: [String: String]
    private var discovered: [String: String] = [:]
    private var didDiscover = false

    private init() {
        working = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    // IDs to try, best first
    func ids(for operation: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        var list: [String] = []
        for id in [working[operation], discovered[operation]].compactMap({ $0 }) + (candidates[operation] ?? []) where !list.contains(id) {
            list.append(id)
        }
        return list
    }

    func markWorking(_ id: String, for operation: String) {
        lock.lock()
        let changed = working[operation] != id
        working[operation] = id
        let snapshot = working
        lock.unlock()
        if changed {
            UserDefaults.standard.set(snapshot, forKey: defaultsKey)
            graphQLLog.notice("using \(operation, privacy: .public) query id \(id, privacy: .public)")
        }
    }

    // Reads query IDs out of X's signed-in web client (its HTML and the scripts it loads). Runs at most once per launch.
    func discover(using client: APIClient, creds: AuthCredentials, completion: @escaping () -> Void) {
        lock.lock()
        if didDiscover { lock.unlock(); completion(); return }
        didDiscover = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String: String] = [:]
            var visited = Set<String>()
            var queue: [URL] = [URL(string: "https://x.com/home")!]
            let scriptPattern = try! NSRegularExpression(pattern: #"https://abs\.twimg\.com/[A-Za-z0-9_./~-]+\.js"#)
            let opPatterns = [
                try! NSRegularExpression(pattern: #"queryId:"([A-Za-z0-9_-]{10,40})",operationName:"([A-Za-z]+)""#),
                try! NSRegularExpression(pattern: #""queryId":"([A-Za-z0-9_-]{10,40})","operationName":"([A-Za-z]+)""#),
                try! NSRegularExpression(pattern: #"operationName:"([A-Za-z]+)"[^}]{0,200}?queryId:"([A-Za-z0-9_-]{10,40})""#)
            ]

            while let url = queue.first, visited.count < 80 {
                queue.removeFirst()
                guard !visited.contains(url.absoluteString) else { continue }
                visited.insert(url.absoluteString)
                guard let text = client.fetchText(url, creds: creds) else { continue }
                let range = NSRange(text.startIndex..., in: text)

                for (index, pattern) in opPatterns.enumerated() {
                    for match in pattern.matches(in: text, range: range) {
                        guard let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { continue }
                        let (id, name) = index == 2 ? (String(text[b]), String(text[a])) : (String(text[a]), String(text[b]))
                        found[name] = id
                    }
                }
                for match in scriptPattern.matches(in: text, range: range) {
                    if let r = Range(match.range, in: text), let next = URL(string: String(text[r])), !visited.contains(next.absoluteString) {
                        queue.append(next)
                    }
                }
            }

            self.lock.lock()
            for (name, id) in found where self.candidates[name] != nil {
                self.discovered[name] = id
            }
            self.lock.unlock()
            graphQLLog.notice("discovered \(found.count, privacy: .public) operations from \(visited.count, privacy: .public) files")
            completion()
        }
    }
}

// MARK: - Requests

extension APIClient {
    private static let profileFeatures: [String: Any] = [
        "hidden_profile_subscriptions_enabled": true,
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "rweb_tipjar_consumption_enabled": true,
        "verified_phone_label_enabled": false,
        "subscriptions_verification_info_is_identity_verified_enabled": true,
        "subscriptions_verification_info_verified_since_enabled": true,
        "highlights_tweets_tab_ui_enabled": true,
        "responsive_web_twitter_article_notes_tab_enabled": true,
        "subscriptions_feature_can_gift_premium": true,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "responsive_web_graphql_exclude_directive_enabled": true,
        "payments_enabled": false,
        "responsive_web_profile_redirect_enabled": false,
        "rweb_video_screen_enabled": false,
        "premium_content_api_read_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
        "responsive_web_grok_analyze_post_followups_enabled": false,
        "responsive_web_jetfuel_frame": false,
        "responsive_web_grok_share_attachment_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "tweet_awards_web_tipping_enabled": false,
        "responsive_web_grok_show_grok_translated_post": false,
        "responsive_web_grok_analysis_button_from_backend": false,
        "creator_subscriptions_quote_tweet_preview_enabled": false,
        "freedom_of_speech_not_reached_appeal_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": true,
        "responsive_web_grok_image_annotation_enabled": true,
        "responsive_web_grok_imagine_annotation_enabled": true,
        "responsive_web_grok_community_note_auto_translation_is_enabled": false,
        "responsive_web_enhance_cards_enabled": false
    ]

    func authorizedRequest(_ url: URL, method: String, creds: AuthCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://x.com/", forHTTPHeaderField: "referer")
        return request
    }

    // Synchronous text fetch for discovery (call off the main thread). Script files don't need the session.
    fileprivate func fetchText(_ url: URL, creds: AuthCredentials) -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if url.host == "x.com" {
            request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var text: String?
        session.dataTask(with: request) { data, response, _ in
            if let data = data, let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                text = String(data: data, encoding: .utf8)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return text
    }

    // GET a GraphQL operation, trying known query IDs in turn (and discovered ones as a last resort)
    func graphQLGet(
        operation: String,
        variables: [String: Any],
        fieldToggles: [String: Any]? = nil,
        usePost: Bool = false,
        completion: @escaping (Result<[String: Any], APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }

        func encode(_ object: [String: Any]) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard let varStr = encode(variables), let featStr = encode(Self.profileFeatures) else {
            completion(.failure(.parseError))
            return
        }
        let toggleStr = fieldToggles.flatMap(encode)

        func attempt(_ ids: [String], tried: Set<String>, discovered: Bool, retriedBest: Bool = false) {
            guard let id = ids.first(where: { !tried.contains($0) }) else {
                if discovered {
                    graphQLLog.error("no working query id for \(operation, privacy: .public)")
                    completion(.failure(.serverError("No working query id for \(operation)")))
                } else {
                    GraphQLOperationIDs.shared.discover(using: self, creds: creds) {
                        attempt(GraphQLOperationIDs.shared.ids(for: operation), tried: tried, discovered: true, retriedBest: retriedBest)
                    }
                }
                return
            }
            var request: URLRequest
            if usePost {
                // Some operations (search) are sent as a JSON POST by X's web client
                var body: [String: Any] = ["variables": variables, "features": Self.profileFeatures, "queryId": id]
                if let fieldToggles = fieldToggles { body["fieldToggles"] = fieldToggles }
                guard let url = URL(string: "https://x.com/i/api/graphql/\(id)/\(operation)"),
                      let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                    completion(.failure(.invalidResponse))
                    return
                }
                request = authorizedRequest(url, method: "POST", creds: creds)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
            } else {
                var comp = URLComponents(string: "https://x.com/i/api/graphql/\(id)/\(operation)")!
                var items = [URLQueryItem(name: "variables", value: varStr), URLQueryItem(name: "features", value: featStr)]
                if let toggleStr = toggleStr { items.append(URLQueryItem(name: "fieldToggles", value: toggleStr)) }
                comp.queryItems = items
                guard let url = comp.url else { completion(.failure(.invalidResponse)); return }
                request = authorizedRequest(url, method: "GET", creds: creds)
            }

            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(.networkError(error)))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(status), let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = json["data"] as? [String: Any], !payload.isEmpty {
                    GraphQLOperationIDs.shared.markWorking(id, for: operation)
                    completion(.success(json))
                    return
                }
                if status == 401 || status == 403 || status == 429 {
                    completion(.failure(.serverError("HTTP \(status)")))
                    return
                }
                let reason = data.flatMap { String(data: $0.prefix(160), encoding: .utf8) } ?? ""
                graphQLLog.notice("\(operation, privacy: .public) id \(id, privacy: .public) failed: HTTP \(status, privacy: .public) \(reason, privacy: .public)")
                // X sometimes rejects a valid query id with 404; give the best id one more try before moving on
                if status == 404 && !retriedBest && id == ids.first {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                        attempt(ids, tried: tried, discovered: discovered, retriedBest: true)
                    }
                    return
                }
                attempt(ids, tried: tried.union([id]), discovered: discovered, retriedBest: retriedBest)
            }.resume()
        }

        attempt(GraphQLOperationIDs.shared.ids(for: operation), tried: [], discovered: false)
    }

    // MARK: People who liked or reposted a post

    func fetchTweetUsers(
        kind: TweetUsersKind,
        tweetId: String,
        cursor: String? = nil,
        completion: @escaping (Result<(users: [TweetUser], bottomCursor: String?), APIError>) -> Void
    ) {
        var variables: [String: Any] = ["tweetId": tweetId, "count": 40, "includePromotedContent": true]
        if let cursor = cursor { variables["cursor"] = cursor }
        graphQLGet(operation: kind.operation, variables: variables) { result in
            switch result {
            case .success(let json):
                var users: [TweetUser] = []
                var seen = Set<String>()
                var bottomCursor: String?
                // The users are the user_results found anywhere in the timeline's entries; the next page's cursor is
                // the entry whose id starts with "cursor-bottom"
                func walk(_ node: Any) {
                    if let dict = node as? [String: Any] {
                        if let results = dict["user_results"] as? [String: Any], let user = results["result"] as? [String: Any] {
                            let parsed = Self.parseUser(user)
                            if !parsed.id.isEmpty, seen.insert(parsed.id).inserted { users.append(parsed) }
                            return
                        }
                        if let entryId = dict["entryId"] as? String, entryId.hasPrefix("cursor-bottom"),
                           let value = (dict["content"] as? [String: Any])?["value"] as? String {
                            bottomCursor = value
                        }
                        for value in dict.values { walk(value) }
                    } else if let array = node as? [Any] {
                        for value in array { walk(value) }
                    }
                }
                walk(json["data"] as Any)
                completion(.success((users, bottomCursor)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: Profile

    func fetchUserProfile(screenName: String, completion: @escaping (Result<UserProfile, APIError>) -> Void) {
        graphQLGet(
            operation: "UserByScreenName",
            variables: ["screen_name": screenName, "withSafetyModeUserFields": true],
            fieldToggles: ["withAuxiliaryUserLabels": false]
        ) { result in
            switch result {
            case .success(let json):
                guard let data = json["data"] as? [String: Any],
                      let user = data["user"] as? [String: Any],
                      let userResult = user["result"] as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                completion(.success(Self.parseProfile(userResult)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func parseProfile(_ userResult: [String: Any]) -> UserProfile {
        let legacy = (userResult["legacy"] as? [String: Any]) ?? [:]
        let core = (userResult["core"] as? [String: Any]) ?? [:]

        // Website: the expanded URL from the profile's URL entity, else the t.co link
        let urlEntity = ((((legacy["entities"] as? [String: Any])?["url"] as? [String: Any])?["urls"] as? [[String: Any]])?.first)
        let rawWebsite = (urlEntity?["expanded_url"] as? String)
            ?? ((userResult["website"] as? [String: Any])?["url"] as? String)
            ?? (legacy["url"] as? String)
        let websiteUrl = rawWebsite.flatMap(URL.init(string:))
        var websiteDisplay = (urlEntity?["display_url"] as? String)
        if websiteDisplay == nil, let url = websiteUrl {
            websiteDisplay = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "") + (url.path.count > 1 ? url.path : "")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        let created = (core["created_at"] as? String) ?? (legacy["created_at"] as? String)

        return UserProfile(
            user: parseUser(userResult),
            websiteUrl: websiteUrl,
            websiteDisplay: websiteDisplay,
            joinedAt: created.flatMap(formatter.date(from:)),
            postsCount: ((userResult["tweet_counts"] as? [String: Any])?["tweets"] as? Int) ?? (legacy["statuses_count"] as? Int),
            isFollowing: ((userResult["relationship_perspectives"] as? [String: Any])?["following"] as? Bool) ?? (legacy["following"] as? Bool) ?? false,
            isProtected: ((userResult["privacy"] as? [String: Any])?["protected"] as? Bool) ?? (legacy["protected"] as? Bool) ?? false
        )
    }

    // MARK: Profile Timelines

    func fetchUserTimeline(
        _ tab: ProfileTab,
        userId: String,
        cursor: String?,
        completion: @escaping (Result<(items: [ProfileTimelineItem], bottomCursor: String?), APIError>) -> Void
    ) {
        var variables: [String: Any] = [
            "userId": userId,
            "count": 20,
            "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true,
            "withVoice": true,
            "withV2Timeline": true
        ]
        switch tab {
        case .posts: break
        case .replies: variables["withCommunity"] = true
        case .media:
            variables["withClientEventToken"] = false
            variables["withBirdwatchNotes"] = false
        }
        if let cursor = cursor { variables["cursor"] = cursor }

        graphQLGet(operation: tab.operationName, variables: variables, fieldToggles: ["withArticlePlainText": false]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                completion(.success(self.parseUserTimeline(json)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseUserTimeline(_ json: [String: Any]) -> (items: [ProfileTimelineItem], bottomCursor: String?) {
        let userResult = ((json["data"] as? [String: Any])?["user"] as? [String: Any])?["result"] as? [String: Any]
        let timelineObj = (userResult?["timeline_v2"] as? [String: Any]) ?? (userResult?["timeline"] as? [String: Any])
        let instructions = ((timelineObj?["timeline"] as? [String: Any])?["instructions"] as? [[String: Any]]) ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"

        var pinned: [ProfileTimelineItem] = []
        var items: [ProfileTimelineItem] = []
        var seen = Set<String>()
        var bottomCursor: String?

        func tweet(_ itemContent: [String: Any]?) -> Tweet? {
            guard let result = (itemContent?["tweet_results"] as? [String: Any])?["result"] as? [String: Any] else { return nil }
            return parseGraphQLTweetResult(result, dateFormatter: formatter)
        }
        func append(_ item: ProfileTimelineItem, to list: inout [ProfileTimelineItem]) {
            guard !seen.contains(item.id) else { return }
            seen.insert(item.id)
            list.append(item)
        }
        // Conversation modules (Replies tab) hold a reply after the post(s) it answers; keep them together as a
        // thread. The Media grid's module is just a run of posts.
        func addModule(_ moduleId: String, _ moduleItems: [[String: Any]]?) {
            let tweets = (moduleItems ?? []).compactMap { tweet(($0["item"] as? [String: Any])?["itemContent"] as? [String: Any]) }
            let isThread = !moduleId.hasPrefix("profile-grid") && tweets.count > 1
            for (index, t) in tweets.enumerated() {
                append(ProfileTimelineItem(
                    id: "\(moduleId)-\(t.id)",
                    tweet: t,
                    threadAbove: isThread && index > 0,
                    threadBelow: isThread && index < tweets.count - 1
                ), to: &items)
            }
        }

        for inst in instructions {
            switch inst["type"] as? String {
            case "TimelinePinEntry":
                let content = (inst["entry"] as? [String: Any])?["content"] as? [String: Any]
                if let t = tweet(content?["itemContent"] as? [String: Any]) {
                    append(ProfileTimelineItem(id: "pinned-\(t.id)", tweet: t, threadAbove: false, threadBelow: false), to: &pinned)
                }
            case "TimelineAddEntries":
                for entry in (inst["entries"] as? [[String: Any]]) ?? [] {
                    let entryId = (entry["entryId"] as? String) ?? ""
                    let content = (entry["content"] as? [String: Any]) ?? [:]
                    switch content["entryType"] as? String {
                    case "TimelineTimelineItem":
                        if let t = tweet(content["itemContent"] as? [String: Any]) {
                            append(ProfileTimelineItem(id: "tweet-\(t.id)", tweet: t, threadAbove: false, threadBelow: false), to: &items)
                        }
                    case "TimelineTimelineModule":
                        addModule(entryId, content["items"] as? [[String: Any]])
                    case "TimelineTimelineCursor":
                        if (content["cursorType"] as? String) == "Bottom" {
                            bottomCursor = content["value"] as? String
                        }
                    default:
                        break
                    }
                }
            case "TimelineAddToModule":
                addModule((inst["moduleEntryId"] as? String) ?? "module", inst["moduleItems"] as? [[String: Any]])
            default:
                break
            }
        }
        // The pinned post also appears in the regular list; show it once, at the top
        let pinnedIds = Set(pinned.map { $0.tweet.id })
        return (pinned + items.filter { !pinnedIds.contains($0.tweet.id) || $0.threadAbove || $0.threadBelow }, bottomCursor)
    }

    // MARK: Follow

    func setFollowing(_ follow: Bool, userId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        let action = follow ? "create" : "destroy"
        var request = authorizedRequest(URL(string: "https://x.com/i/api/1.1/friendships/\(action).json")!, method: "POST", creds: creds)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "include_profile_interstitial_type=1&skip_status=true&user_id=\(userId)".data(using: .utf8)
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion((200...299).contains(status) ? .success(()) : .failure(.serverError(Self.errorMessage(from: data) ?? "HTTP \(status)")))
        }.resume()
    }
}

// Which list of people to show for a post
enum TweetUsersKind: String {
    case likes, reposts

    var operation: String { self == .likes ? "Favoriters" : "Retweeters" }
}
