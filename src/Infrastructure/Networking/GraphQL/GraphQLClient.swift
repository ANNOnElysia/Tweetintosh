//
//  GraphQLClient.swift
//  Tweetintosh
//
//  X's GraphQL operations: the query IDs they are addressed by, discovery from X's web client, and the one
//  authenticated request path every feature reads through.
//

import Foundation
import os

let graphQLLog = Logger(subsystem: "com.anno.tweetintosh", category: "graphql")

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
        // Who an account follows, and who follows it: read from X's web client on first use, like the two above
        "Following": [],
        "Followers": [],
        "DeleteTweet": ["VaenaVgh5q5ih7kvyVjgtg"],
        "composerCardPreviewQuery": ["C1r84YfBL_DG4qOwIaQfjA"],
        "UserMedia": [
            "eF8kYZ4r9zFLqcYno3I17A", "oMVVrI5kt3kOpyHHTTKf5Q","BGmkmGDG0kZPM-aoQtNTTw", "dexO_2tohK86JDudXXG3Yw",
            "MOLbHrtk8Ovu7DUNOLcXiA", "Le6KlbilFmSu-5VltFND-Q"
        ],
        // The Bookmarks page's timeline. Known ids first; X's web client is read for the current one if they fail.
        "Bookmarks": [
            "tmd4ifV8RHltzn8ymGg1aw", "xLjCVTqYWz8CGSprLU349w", "QUjXply7fA7fk05FRyajEg"
        ],
        "CreateTweet": [
            "5CVj-J0FZWyGgJpcjeBJEA", "jm93VcEnLxM7My_CL9C_EA", "znCVAd692dKBq9MgkEhKPQ", "TAJw1rBsjAtdNgTdlo2oeg"
        ],
        // These live in a script X's client only loads on demand, which discovery doesn't reach, so they can't be
        // repaired automatically when X changes them
        "ListOwnerships": ["6spVXajXDiSz025ZUwzOfQ"],
        "ListAddMember": ["-Kf1YVC1rNKkPvPFk7YXZw"],
        "ListRemoveMember": ["_2o1-wSMWGFSi5HUscn1Hw"],
        // The Videos tab's feed. It lives in an on-demand script too, but one discovery can reach: see onDemandBundles.
        "ImmersiveMedia": ["i2LFCbu4bShqaSoQ0tMCKw"]
    ]

    // On-demand scripts whose operations discovery should read. X's page names its on-demand chunks by number in an
    // inline map ("22766:"bundle.ImmersiveMediaViewer"") with a second map from the same number to the file's hash, and
    // the file is <name>.<hash>a.js; no script on the page spells that address out, so it has to be put together here.
    private static let onDemandBundles = ["bundle.ImmersiveMediaViewer"]

    private static func onDemandScriptURLs(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return onDemandBundles.compactMap { name in
            let escaped = NSRegularExpression.escapedPattern(for: name)
            guard let idPattern = try? NSRegularExpression(pattern: "(\\d+):\"" + escaped + "\""),
                  let idMatch = idPattern.firstMatch(in: text, range: range),
                  let idRange = Range(idMatch.range(at: 1), in: text) else { return nil }
            let chunkId = String(text[idRange])
            guard let hashPattern = try? NSRegularExpression(pattern: "[{,]" + chunkId + ":\"([0-9a-f]{8,24})\""),
                  let hashMatch = hashPattern.firstMatch(in: text, range: range),
                  let hashRange = Range(hashMatch.range(at: 1), in: text) else { return nil }
            return URL(string: "https://abs.twimg.com/responsive-web/client-web/\(name).\(text[hashRange])a.js")
        }
    }

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
                // First, so the 80-file limit can't leave them out
                for next in Self.onDemandScriptURLs(in: text) where !visited.contains(next.absoluteString) {
                    queue.insert(next, at: 0)
                }

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
    /// The feature flags X's web client sends with GraphQL reads. Some operations add flags of their own on top.
    static let graphQLFeatures: [String: Any] = [
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
        extraFeatures: [String: Any] = [:],
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
        // Some operations insist on a flag of their own on top of the shared set, and refuse the request without it
        let features = Self.graphQLFeatures.merging(extraFeatures) { _, extra in extra }
        guard let varStr = encode(variables), let featStr = encode(features) else {
            completion(.failure(.parseError))
            return
        }
        let toggleStr = fieldToggles.flatMap(encode)

        func attempt(_ ids: [String], tried: Set<String>, discovered: Bool, retriedBest: Bool = false) {
            guard let id = ids.first(where: { !tried.contains($0) }) else {
                if discovered {
                    graphQLLog.error("no working query id for \(operation, privacy: .public)")
                    completion(.failure(.serverError(LocalizationManager.shared.t("error_query_id_missing"))))
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
                var body: [String: Any] = ["variables": variables, "features": features, "queryId": id]
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
                    let body = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? ""
                    graphQLLog.error("\(operation, privacy: .public) refused: HTTP \(status, privacy: .public) \(body, privacy: .public)")
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
}
