//
//  APIClient.swift
//  MaX - Headless Data-driven Client
//

import Foundation

enum APIError: LocalizedError {
    case unauthenticated
    case invalidResponse
    case networkError(Error)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .unauthenticated: return "Not authenticated. Please sign in."
        case .invalidResponse: return "Received invalid response from server."
        case .networkError(let err): return err.localizedDescription
        case .parseError: return "Failed to parse timeline data."
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private let bearerToken = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Fetch GraphQL Home Timeline (For You & Following)
    func fetchGraphQLHomeTimeline(
        feedType: HomeFeedType,
        cursor: String? = nil,
        seenTweetIds: [String] = [],
        completion: @escaping (Result<(tweets: [Tweet], topCursor: String?, bottomCursor: String?), APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let queryId: String
        let endpoint: String
        var variables: [String: Any] = [
            "count": 20,
            "includePromotedContent": false,
            "requestContext": "launch",
            "seenTweetIds": seenTweetIds
        ]
        
        switch feedType {
        case .forYou:
            queryId = "-SBRQaLiRjWvTFD5SI403A"
            endpoint = "https://x.com/i/api/graphql/\(queryId)/HomeTimeline"
            variables["withCommunity"] = true
        case .following:
            queryId = "hB-6CNtJdReMJny7IPMoQQ"
            endpoint = "https://x.com/i/api/graphql/\(queryId)/HomeLatestTimeline"
            variables["enableRanking"] = false
        }
        
        if let cursor = cursor {
            variables["cursor"] = cursor
        }
        
        let features: [String: Any] = [
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "articles_preview_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true
        ]
        
        guard let requestURL = URL(string: endpoint) else {
            completion(.failure(.parseError))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let payload: [String: Any] = [
            "variables": variables,
            "features": features,
            "queryId": queryId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                // Fall back to REST timeline if GraphQL fails
                self.fetchHomeTimeline(cursor: cursor, completion: completion)
                return
            }
            
            do {
                let parsed = try self.parseGraphQLTimeline(data)
                if parsed.tweets.isEmpty && cursor == nil {
                    // Fall back to REST timeline if empty
                    self.fetchHomeTimeline(cursor: cursor, completion: completion)
                } else {
                    completion(.success(parsed))
                }
            } catch {
                self.fetchHomeTimeline(cursor: cursor, completion: completion)
            }
        }
        task.resume()
    }
    
    // MARK: - Parse GraphQL Timeline URT JSON
    func parseGraphQLTimeline(_ data: Data) throws -> (tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let home = dataDict["home"] as? [String: Any],
              let timeline = home["home_timeline_urt"] as? [String: Any],
              let instructions = timeline["instructions"] as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        
        var orderedTweets: [Tweet] = []
        var seenIds = Set<String>()
        var topCursor: String?
        var bottomCursor: String?
        
        for inst in instructions {
            let entries = (inst["entries"] as? [[String: Any]]) ?? []
            for e in entries {
                let eid = e["entryId"] as? String ?? ""
                
                if eid.hasPrefix("cursor-top-") {
                    if let content = e["content"] as? [String: Any],
                       let val = content["value"] as? String {
                        topCursor = val
                    }
                } else if eid.hasPrefix("cursor-bottom-") {
                    if let content = e["content"] as? [String: Any],
                       let val = content["value"] as? String {
                        bottomCursor = val
                    }
                } else if eid.hasPrefix("tweet-") {
                    if let tweet = self.buildGraphQLTweet(entry: e, dateFormatter: dateFormatter) {
                        if !seenIds.contains(tweet.id) {
                            seenIds.insert(tweet.id)
                            orderedTweets.append(tweet)
                        }
                    }
                }
            }
        }
        
        return (orderedTweets, topCursor, bottomCursor)
    }
    
    private func buildGraphQLTweet(entry: [String: Any], dateFormatter: DateFormatter) -> Tweet? {
        guard let content = entry["content"] as? [String: Any],
              let itemContent = content["itemContent"] as? [String: Any],
              let tweetResults = itemContent["tweet_results"] as? [String: Any],
              var result = tweetResults["result"] as? [String: Any] else {
            return nil
        }
        
        // Unwrap TweetWithVisibilityResults
        if let inner = result["tweet"] as? [String: Any] {
            result = inner
        }
        
        guard let restId = result["rest_id"] as? String,
              var legacy = result["legacy"] as? [String: Any] else {
            return nil
        }
        
        var isRetweet = false
        var retweetedBy: String?
        
        // Handle Retweet in GraphQL
        if let rtResult = legacy["retweeted_status_result"] as? [String: Any],
           var original = rtResult["result"] as? [String: Any] {
            isRetweet = true
            if let innerRt = original["tweet"] as? [String: Any] {
                original = innerRt
            }
            if let rtLegacy = original["legacy"] as? [String: Any] {
                let curCore = (result["core"] as? [String: Any]) ?? [:]
                let curUserRes = (curCore["user_results"] as? [String: Any]) ?? [:]
                let curUser = (curUserRes["result"] as? [String: Any]) ?? [:]
                let curUCore = (curUser["core"] as? [String: Any]) ?? [:]
                let curULegacy = (curUser["legacy"] as? [String: Any]) ?? [:]
                retweetedBy = (curUCore["name"] as? String) ?? (curULegacy["name"] as? String)
                
                legacy = rtLegacy
                result = original
            }
        }
        
        let fullText = (legacy["full_text"] as? String) ?? (legacy["text"] as? String) ?? ""
        let createdAtStr = legacy["created_at"] as? String ?? ""
        let createdAt = dateFormatter.date(from: createdAtStr) ?? Date()
        
        // Author extraction
        let core = (result["core"] as? [String: Any]) ?? [:]
        let userResults = (core["user_results"] as? [String: Any]) ?? [:]
        let userResult = (userResults["result"] as? [String: Any]) ?? [:]
        let ucore = (userResult["core"] as? [String: Any]) ?? [:]
        let ulegacy = (userResult["legacy"] as? [String: Any]) ?? [:]
        let uavatar = (userResult["avatar"] as? [String: Any]) ?? [:]
        
        let userName = (ucore["name"] as? String) ?? (ulegacy["name"] as? String) ?? "User"
        let screenName = (ucore["screen_name"] as? String) ?? (ulegacy["screen_name"] as? String) ?? ""
        let rawAvatar = (uavatar["image_url"] as? String) ?? (ulegacy["profile_image_url_https"] as? String)
        let avatarUrl = rawAvatar?.replacingOccurrences(of: "_normal", with: "_bigger")
        let isVerified = (userResult["is_blue_verified"] as? Bool) ?? (ulegacy["verified"] as? Bool) ?? false
        let authorId = (userResult["rest_id"] as? String) ?? (userResult["id"] as? String) ?? ""
        
        let author = TweetUser(
            id: authorId,
            name: userName,
            screenName: screenName,
            avatarUrl: avatarUrl,
            isVerified: isVerified
        )
        
        // Media extraction
        var mediaList: [TweetMedia] = []
        if let extendedEntities = legacy["extended_entities"] as? [String: Any],
           let mediaItems = extendedEntities["media"] as? [[String: Any]] {
            for m in mediaItems {
                if let mId = m["id_str"] as? String,
                   let mType = m["type"] as? String,
                   let mUrl = m["media_url_https"] as? String {
                    let sizes = m["sizes"] as? [String: Any]
                    let large = sizes?["large"] as? [String: Any]
                    let width = (large?["w"] as? Int) ?? 800
                    let height = (large?["h"] as? Int) ?? 600
                    
                    mediaList.append(TweetMedia(
                        id: mId,
                        type: mType,
                        mediaUrl: mUrl,
                        previewUrl: mUrl,
                        width: width,
                        height: height
                    ))
                }
            }
        }
        
        let replyCount = (legacy["reply_count"] as? Int) ?? 0
        let retweetCount = (legacy["retweet_count"] as? Int) ?? 0
        let favoriteCount = (legacy["favorite_count"] as? Int) ?? 0
        
        return Tweet(
            id: restId,
            text: fullText,
            createdAt: createdAt,
            author: author,
            media: mediaList,
            replyCount: replyCount,
            retweetCount: retweetCount,
            favoriteCount: favoriteCount,
            isRetweet: isRetweet,
            retweetedBy: retweetedBy
        )
    }
    
    // MARK: - Legacy Fetch Home Timeline
    func fetchHomeTimeline(
        cursor: String? = nil,
        completion: @escaping (Result<(tweets: [Tweet], topCursor: String?, bottomCursor: String?), APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        var urlComponents = URLComponents(string: "https://x.com/i/api/2/timeline/home.json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "count", value: "35"),
            URLQueryItem(name: "include_profile_interstitial_type", value: "1"),
            URLQueryItem(name: "include_blocking", value: "1"),
            URLQueryItem(name: "include_blocked_by", value: "1"),
            URLQueryItem(name: "include_followed_by", value: "1"),
            URLQueryItem(name: "include_want_retweets", value: "1"),
            URLQueryItem(name: "include_mute_edge", value: "1"),
            URLQueryItem(name: "include_can_dm", value: "1"),
            URLQueryItem(name: "include_can_media_tag", value: "1"),
            URLQueryItem(name: "include_ext_has_nft_avatar", value: "1"),
            URLQueryItem(name: "include_ext_is_blue_verified", value: "1"),
            URLQueryItem(name: "include_ext_verified_type", value: "1"),
            URLQueryItem(name: "skip_status", value: "1"),
            URLQueryItem(name: "cards_platform", value: "Web-12"),
            URLQueryItem(name: "include_cards", value: "1"),
            URLQueryItem(name: "include_ext_alt_text", value: "true"),
            URLQueryItem(name: "include_ext_limited_action_results", value: "true"),
            URLQueryItem(name: "include_quote_count", value: "true"),
            URLQueryItem(name: "include_reply_count", value: "1"),
            URLQueryItem(name: "tweet_mode", value: "extended"),
            URLQueryItem(name: "include_ext_views", value: "true"),
            URLQueryItem(name: "include_entities", value: "true")
        ]
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        urlComponents.queryItems = queryItems
        
        guard let requestURL = urlComponents.url else {
            completion(.failure(.parseError))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("en", forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                let parsed = try self.parseTimelineV2JSON(data)
                completion(.success(parsed))
            } catch {
                completion(.failure(.parseError))
            }
        }
        task.resume()
    }
    
    // MARK: - Fetch Notifications Timeline
    func fetchNotifications(
        cursor: String? = nil,
        completion: @escaping (Result<(items: [NotificationItem], topCursor: String?, bottomCursor: String?), APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        var urlComponents = URLComponents(string: "https://x.com/i/api/2/notifications/all.json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "count", value: "35"),
            URLQueryItem(name: "include_profile_interstitial_type", value: "1"),
            URLQueryItem(name: "include_blocking", value: "1"),
            URLQueryItem(name: "include_blocked_by", value: "1"),
            URLQueryItem(name: "include_followed_by", value: "1"),
            URLQueryItem(name: "include_want_retweets", value: "1"),
            URLQueryItem(name: "include_mute_edge", value: "1"),
            URLQueryItem(name: "include_can_dm", value: "1"),
            URLQueryItem(name: "include_can_media_tag", value: "1"),
            URLQueryItem(name: "include_ext_has_nft_avatar", value: "1"),
            URLQueryItem(name: "include_ext_is_blue_verified", value: "1"),
            URLQueryItem(name: "include_ext_verified_type", value: "1"),
            URLQueryItem(name: "skip_status", value: "1"),
            URLQueryItem(name: "cards_platform", value: "Web-12"),
            URLQueryItem(name: "include_cards", value: "1"),
            URLQueryItem(name: "include_ext_alt_text", value: "true"),
            URLQueryItem(name: "include_ext_limited_action_results", value: "true"),
            URLQueryItem(name: "include_quote_count", value: "true"),
            URLQueryItem(name: "include_reply_count", value: "1"),
            URLQueryItem(name: "tweet_mode", value: "extended"),
            URLQueryItem(name: "include_ext_views", value: "true"),
            URLQueryItem(name: "include_entities", value: "true")
        ]
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        urlComponents.queryItems = queryItems
        
        guard let requestURL = urlComponents.url else {
            completion(.failure(.parseError))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("en", forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                let parsed = try self.parseNotificationsJSON(data)
                completion(.success(parsed))
            } catch {
                completion(.failure(.parseError))
            }
        }
        task.resume()
    }
    
    // MARK: - Parse Notifications JSON
    private func parseNotificationsJSON(_ data: Data) throws -> (items: [NotificationItem], topCursor: String?, bottomCursor: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let globalObjects = json["globalObjects"] as? [String: Any],
              let notifsDict = globalObjects["notifications"] as? [String: [String: Any]] else {
            throw APIError.parseError
        }
        
        let tweetsDict = (globalObjects["tweets"] as? [String: [String: Any]]) ?? [:]
        let usersDict = (globalObjects["users"] as? [String: [String: Any]]) ?? [:]
        
        let timeline = json["timeline"] as? [String: Any]
        let instructions = (timeline?["instructions"] as? [[String: Any]]) ?? []
        
        var orderedItems: [NotificationItem] = []
        var seenIds = Set<String>()
        var topCursor: String?
        var bottomCursor: String?
        
        for inst in instructions {
            guard let addEntries = inst["addEntries"] as? [String: Any],
                  let entries = addEntries["entries"] as? [[String: Any]] else {
                continue
            }
            
            for entry in entries {
                let entryId = entry["entryId"] as? String ?? ""
                
                if entryId.hasPrefix("cursor-top-") {
                    if let content = entry["content"] as? [String: Any],
                       let op = content["operation"] as? [String: Any],
                       let cursorObj = op["cursor"] as? [String: Any],
                       let val = cursorObj["value"] as? String {
                        topCursor = val
                    }
                } else if entryId.hasPrefix("cursor-bottom-") {
                    if let content = entry["content"] as? [String: Any],
                       let op = content["operation"] as? [String: Any],
                       let cursorObj = op["cursor"] as? [String: Any],
                       let val = cursorObj["value"] as? String {
                        bottomCursor = val
                    }
                } else if entryId.hasPrefix("notification-") {
                    let nid = entryId.replacingOccurrences(of: "notification-", with: "")
                    if let item = self.buildNotificationItem(nid: nid, entry: entry, notifsDict: notifsDict, tweetsDict: tweetsDict, usersDict: usersDict) {
                        if !seenIds.contains(item.id) {
                            seenIds.insert(item.id)
                            orderedItems.append(item)
                        }
                    }
                }
            }
        }
        
        // Fallback: if addEntries had no notification items, parse notifsDict directly
        if orderedItems.isEmpty {
            for (nid, _) in notifsDict {
                if let item = self.buildNotificationItem(nid: nid, entry: [:], notifsDict: notifsDict, tweetsDict: tweetsDict, usersDict: usersDict) {
                    if !seenIds.contains(item.id) {
                        seenIds.insert(item.id)
                        orderedItems.append(item)
                    }
                }
            }
            orderedItems.sort { $0.createdAt > $1.createdAt }
        }
        
        return (orderedItems, topCursor, bottomCursor)
    }
    
    private func buildNotificationItem(
        nid: String,
        entry: [String: Any],
        notifsDict: [String: [String: Any]],
        tweetsDict: [String: [String: Any]],
        usersDict: [String: [String: Any]]
    ) -> NotificationItem? {
        guard let notif = notifsDict[nid] else { return nil }
        
        let iconDict = notif["icon"] as? [String: Any]
        let iconId = iconDict?["id"] as? String ?? ""
        let msgDict = notif["message"] as? [String: Any]
        let actionSummary = msgDict?["text"] as? String ?? ""
        
        let timestampMs = (notif["timestampMs"] as? String).flatMap { Double($0) }
            ?? (entry["sortIndex"] as? String).flatMap { Double($0) }
            ?? (Date().timeIntervalSince1970 * 1000.0)
        let createdAt = Date(timeIntervalSince1970: timestampMs / 1000.0)
        
        // Notification Type
        let notifType: NotificationType
        switch iconId {
        case "heart_icon":
            notifType = .like
        case "retweet_icon":
            notifType = .retweet
        case "reply_icon":
            notifType = .reply
        case "person_icon":
            notifType = .follow
        default:
            if actionSummary.localizedCaseInsensitiveContains("liked") {
                notifType = .like
            } else if actionSummary.localizedCaseInsensitiveContains("reposted") || actionSummary.localizedCaseInsensitiveContains("retweeted") {
                notifType = .retweet
            } else if actionSummary.localizedCaseInsensitiveContains("replied") {
                notifType = .reply
            } else if actionSummary.localizedCaseInsensitiveContains("followed") {
                notifType = .follow
            } else {
                notifType = .mention
            }
        }
        
        // Extract Actors
        var actors: [TweetUser] = []
        let template = notif["template"] as? [String: Any]
        let actions = template?["aggregateUserActionsV1"] as? [String: Any]
        
        if let fromUsers = actions?["fromUsers"] as? [[String: Any]] {
            for fu in fromUsers {
                if let userObj = fu["user"] as? [String: Any],
                   let uid = userObj["id"] as? String,
                   let u = usersDict[uid] {
                    let name = u["name"] as? String ?? ""
                    let screenName = u["screen_name"] as? String ?? ""
                    let avatarUrl = (u["profile_image_url_https"] as? String)?
                        .replacingOccurrences(of: "_normal", with: "_bigger")
                    let isVerified = (u["verified"] as? Bool) ?? (u["is_blue_verified"] as? Bool) ?? false
                    actors.append(TweetUser(id: uid, name: name, screenName: screenName, avatarUrl: avatarUrl, isVerified: isVerified))
                }
            }
        }
        
        if actors.isEmpty, let entities = msgDict?["entities"] as? [[String: Any]] {
            for ent in entities {
                if let ref = ent["ref"] as? [String: Any],
                   let userRef = ref["user"] as? [String: Any],
                   let uid = userRef["id"] as? String,
                   let u = usersDict[uid] {
                    let name = u["name"] as? String ?? ""
                    let screenName = u["screen_name"] as? String ?? ""
                    let avatarUrl = (u["profile_image_url_https"] as? String)?
                        .replacingOccurrences(of: "_normal", with: "_bigger")
                    let isVerified = (u["verified"] as? Bool) ?? (u["is_blue_verified"] as? Bool) ?? false
                    actors.append(TweetUser(id: uid, name: name, screenName: screenName, avatarUrl: avatarUrl, isVerified: isVerified))
                }
            }
        }
        
        // Target Tweet Snippet
        var targetTweetSnippet: String?
        if let targetObjects = actions?["targetObjects"] as? [[String: Any]] {
            for to in targetObjects {
                if let tweetObj = to["tweet"] as? [String: Any],
                   let tid = tweetObj["id"] as? String,
                   let tweet = tweetsDict[tid] {
                    targetTweetSnippet = tweet["full_text"] as? String
                    break
                }
            }
        }
        
        return NotificationItem(
            id: nid,
            type: notifType,
            actors: actors,
            actionSummary: actionSummary,
            targetTweetSnippet: targetTweetSnippet,
            replyBody: nil,
            createdAt: createdAt
        )
    }
    
    // MARK: - JSON Parser (URT v2 Timeline)
    private func parseTimelineV2JSON(_ data: Data) throws -> (tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let globalObjects = json["globalObjects"] as? [String: Any],
              let tweetsDict = globalObjects["tweets"] as? [String: [String: Any]],
              let usersDict = globalObjects["users"] as? [String: [String: Any]] else {
            throw APIError.parseError
        }
        
        let timeline = json["timeline"] as? [String: Any]
        let instructions = (timeline?["instructions"] as? [[String: Any]]) ?? []
        
        var orderedTweets: [Tweet] = []
        var topCursor: String?
        var bottomCursor: String?
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        
        // Find addEntries instruction
        for inst in instructions {
            guard let addEntries = inst["addEntries"] as? [String: Any],
                  let entries = addEntries["entries"] as? [[String: Any]] else {
                continue
            }
            
            for entry in entries {
                let entryId = entry["entryId"] as? String ?? ""
                
                // Cursors
                if entryId.hasPrefix("cursor-top-") {
                    if let content = entry["content"] as? [String: Any],
                       let op = content["operation"] as? [String: Any],
                       let cursorObj = op["cursor"] as? [String: Any],
                       let val = cursorObj["value"] as? String {
                        topCursor = val
                    }
                } else if entryId.hasPrefix("cursor-bottom-") {
                    if let content = entry["content"] as? [String: Any],
                       let op = content["operation"] as? [String: Any],
                       let cursorObj = op["cursor"] as? [String: Any],
                       let val = cursorObj["value"] as? String {
                        bottomCursor = val
                    }
                }
                
                // Tweet
                if entryId.hasPrefix("tweet-") {
                    let tweetId = entryId.replacingOccurrences(of: "tweet-", with: "")
                    if let tweetObj = tweetsDict[tweetId] {
                        if let tweet = buildTweet(from: tweetObj, tweetsDict: tweetsDict, usersDict: usersDict, dateFormatter: dateFormatter) {
                            orderedTweets.append(tweet)
                        }
                    }
                }
            }
        }
        
        // Fallback: If instructions didn't list entries, pull directly from tweetsDict
        if orderedTweets.isEmpty && !tweetsDict.isEmpty {
            for (_, tweetObj) in tweetsDict {
                if let tweet = buildTweet(from: tweetObj, tweetsDict: tweetsDict, usersDict: usersDict, dateFormatter: dateFormatter) {
                    orderedTweets.append(tweet)
                }
            }
            orderedTweets.sort { $0.createdAt > $1.createdAt }
        }
        
        return (orderedTweets, topCursor, bottomCursor)
    }
    
    private func buildTweet(
        from raw: [String: Any],
        tweetsDict: [String: [String: Any]],
        usersDict: [String: [String: Any]],
        dateFormatter: DateFormatter
    ) -> Tweet? {
        var tweetObj = raw
        var isRetweet = false
        var retweetedBy: String?
        
        // Handle Retweet
        if let rtId = raw["retweeted_status_id_str"] as? String, let original = tweetsDict[rtId] {
            isRetweet = true
            if let rtUserId = raw["user_id_str"] as? String, let rtUser = usersDict[rtUserId] {
                retweetedBy = rtUser["name"] as? String
            }
            tweetObj = original
        }
        
        guard let idStr = tweetObj["id_str"] as? String,
              let fullText = (tweetObj["full_text"] as? String) ?? (tweetObj["text"] as? String),
              let userIdStr = tweetObj["user_id_str"] as? String,
              let userObj = usersDict[userIdStr],
              let userName = userObj["name"] as? String,
              let screenName = userObj["screen_name"] as? String else {
            return nil
        }
        
        let avatarUrl = (userObj["profile_image_url_https"] as? String)?
            .replacingOccurrences(of: "_normal", with: "_bigger")
        let isVerified = (userObj["is_blue_verified"] as? Bool) ?? (userObj["verified"] as? Bool) ?? false
        
        let createdAtStr = tweetObj["created_at"] as? String ?? ""
        let createdAt = dateFormatter.date(from: createdAtStr) ?? Date()
        
        let author = TweetUser(
            id: userIdStr,
            name: userName,
            screenName: screenName,
            avatarUrl: avatarUrl,
            isVerified: isVerified
        )
        
        // Extract Media
        var mediaList: [TweetMedia] = []
        if let extendedEntities = tweetObj["extended_entities"] as? [String: Any],
           let mediaItems = extendedEntities["media"] as? [[String: Any]] {
            for m in mediaItems {
                if let mId = m["id_str"] as? String,
                   let mType = m["type"] as? String,
                   let mUrl = m["media_url_https"] as? String {
                    let sizes = m["sizes"] as? [String: Any]
                    let large = sizes?["large"] as? [String: Any]
                    let width = (large?["w"] as? Int) ?? 800
                    let height = (large?["h"] as? Int) ?? 600
                    
                    mediaList.append(TweetMedia(
                        id: mId,
                        type: mType,
                        mediaUrl: mUrl,
                        previewUrl: mUrl,
                        width: width,
                        height: height
                    ))
                }
            }
        }
        
        let replyCount = (tweetObj["reply_count"] as? Int) ?? 0
        let retweetCount = (tweetObj["retweet_count"] as? Int) ?? 0
        let favoriteCount = (tweetObj["favorite_count"] as? Int) ?? 0
        
        return Tweet(
            id: idStr,
            text: fullText,
            createdAt: createdAt,
            author: author,
            media: mediaList,
            replyCount: replyCount,
            retweetCount: retweetCount,
            favoriteCount: favoriteCount,
            isRetweet: isRetweet,
            retweetedBy: retweetedBy
        )
    }
}
