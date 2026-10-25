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
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .unauthenticated: return "Not authenticated. Please sign in."
        case .invalidResponse: return "Received invalid response from server."
        case .networkError(let err): return err.localizedDescription
        case .parseError: return "Failed to parse timeline data."
        case .serverError(let msg): return msg
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    
    let session: URLSession
    let bearerToken = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    var clientLanguageHeader: String {
        switch LocalizationManager.shared.currentLanguage {
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .simplifiedChinese: return "zh-cn"
        case .traditionalChinese: return "zh-tw"
        }
    }
    
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
            "includePromotedContent": ThemeManager.shared.showPromotedPosts,
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
        case .list:
            queryId = "uV0pbd0DrW8hTbMrtZ1SYQ"
            endpoint = ""
        }
        
        // Handle List timeline with GET method as expected by Twitter
        if feedType == .list {
            let listId = TimelineViewModel.shared.selectedListId
            guard !listId.isEmpty else {
                completion(.success(([], nil, nil)))
                return
            }
            
            var listVariables: [String: Any] = ["listId": listId, "count": 20]
            if let cursor = cursor {
                listVariables["cursor"] = cursor
            }
            let listFeatures: [String: Any] = [
                "responsive_web_graphql_timeline_navigation_enabled": true,
                "creator_subscriptions_tweet_preview_api_enabled": true,
                "responsive_web_edit_tweet_api_enabled": true,
                "articles_preview_enabled": true,
                "view_counts_everywhere_api_enabled": true,
                "longform_notetweets_consumption_enabled": true,
                "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
                "responsive_web_twitter_article_tweet_consumption_enabled": true
            ]
            
            guard let varData = try? JSONSerialization.data(withJSONObject: listVariables),
                  let featData = try? JSONSerialization.data(withJSONObject: listFeatures),
                  let varStr = String(data: varData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let featStr = String(data: featData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let listURL = URL(string: "https://x.com/i/api/graphql/\(queryId)/ListLatestTweetsTimeline?variables=\(varStr)&features=\(featStr)") else {
                completion(.failure(.parseError))
                return
            }
            
            var request = URLRequest(url: listURL)
            request.httpMethod = "GET"
            request.setValue(bearerToken, forHTTPHeaderField: "authorization")
            request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
            request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
            request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
            request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
            request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
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
                    let parsed = try self.parseGraphQLTimeline(data)
                    completion(.success(parsed))
                } catch {
                    completion(.failure(.parseError))
                }
            }
            task.resume()
            return
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
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
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
              let dataDict = json["data"] as? [String: Any] else {
            throw APIError.parseError
        }
        
        var instructions: [[String: Any]]?
        if let home = dataDict["home"] as? [String: Any],
           let timeline = home["home_timeline_urt"] as? [String: Any],
           let inst = timeline["instructions"] as? [[String: Any]] {
            instructions = inst
        } else if let list = dataDict["list"] as? [String: Any],
                  let tweetsTimeline = list["tweets_timeline"] as? [String: Any],
                  let timeline = tweetsTimeline["timeline"] as? [String: Any],
                  let inst = timeline["instructions"] as? [[String: Any]] {
            instructions = inst
        }
        
        guard let instructions = instructions else {
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
                } else if eid.hasPrefix("tweet-") || (ThemeManager.shared.showPromotedPosts && (eid.hasPrefix("promoted-tweet-") || eid.hasPrefix("promotedTweet-") || eid.lowercased().contains("promoted"))) {
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
    
    private func isPromotedEntry(
        entryId: String,
        itemContent: [String: Any]? = nil,
        itemObj: [String: Any]? = nil,
        resultObj: [String: Any]? = nil
    ) -> Bool {
        if entryId.lowercased().contains("promoted") {
            return true
        }
        if let itemContent = itemContent {
            if itemContent["promotedMetadata"] != nil { return true }
            if let type = itemContent["itemContentType"] as? String, type.lowercased().contains("promoted") {
                return true
            }
        }
        if let itemObj = itemObj {
            if let clientEvent = itemObj["clientEventInfo"] as? [String: Any],
               let comp = clientEvent["component"] as? String,
               comp.lowercased().contains("promoted") {
                return true
            }
        }
        if let resultObj = resultObj {
            if resultObj["promoted_metadata"] != nil || resultObj["promotedMetadata"] != nil {
                return true
            }
            if let typename = resultObj["__typename"] as? String, typename.lowercased().contains("promoted") {
                return true
            }
        }
        return false
    }
    
    private func buildGraphQLTweet(entry: [String: Any], dateFormatter: DateFormatter) -> Tweet? {
        let eid = (entry["entryId"] as? String) ?? ""
        guard let content = entry["content"] as? [String: Any],
              let itemContent = content["itemContent"] as? [String: Any],
              let tweetResults = itemContent["tweet_results"] as? [String: Any],
              let result = tweetResults["result"] as? [String: Any] else {
            return nil
        }
        let isPromoted = self.isPromotedEntry(entryId: eid, itemContent: itemContent, itemObj: content, resultObj: result)
        if isPromoted && !ThemeManager.shared.showPromotedPosts {
            return nil
        }
        guard var tweet = parseGraphQLTweetResult(result, dateFormatter: dateFormatter) else {
            return nil
        }
        if isPromoted {
            tweet.isPromoted = true
        }
        return tweet
    }
    
    func parseGraphQLTweetResult(_ rawResult: [String: Any], dateFormatter: DateFormatter, parseQuoted: Bool = true) -> Tweet? {
        var result = rawResult
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
        let author = Self.parseUser((userResults["result"] as? [String: Any]) ?? [:])
        
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
                    
                    var videoInfo: TweetVideoInfo? = nil
                    if let vInfo = m["video_info"] as? [String: Any] {
                        let durationMillis = vInfo["duration_millis"] as? Int
                        let ar = vInfo["aspect_ratio"] as? [Int]
                        var variants: [TweetVideoVariant] = []
                        if let vList = vInfo["variants"] as? [[String: Any]] {
                            for v in vList {
                                if let cType = v["content_type"] as? String,
                                   let vUrl = v["url"] as? String {
                                    let br = v["bitrate"] as? Int
                                    variants.append(TweetVideoVariant(contentType: cType, url: vUrl, bitrate: br))
                                }
                            }
                        }
                        videoInfo = TweetVideoInfo(durationMillis: durationMillis, aspectRatio: ar, variants: variants)
                    }
                    
                    mediaList.append(TweetMedia(
                        id: mId,
                        type: mType,
                        mediaUrl: mUrl,
                        previewUrl: mUrl,
                        width: width,
                        height: height,
                        videoInfo: videoInfo
                    ))
                }
            }
        }
        
        let replyCount = (legacy["reply_count"] as? Int) ?? 0
        let retweetCount = (legacy["retweet_count"] as? Int) ?? 0
        let favoriteCount = (legacy["favorite_count"] as? Int) ?? 0
        let isFavorited = (legacy["favorited"] as? Bool) ?? ((legacy["favorited"] as? NSNumber)?.boolValue ?? false)
        let isRetweeted = (legacy["retweeted"] as? Bool) ?? ((legacy["retweeted"] as? NSNumber)?.boolValue ?? false)
        let isBookmarked = (legacy["bookmarked"] as? Bool) ?? ((legacy["bookmarked"] as? NSNumber)?.boolValue ?? false)
        let bookmarkCount = (legacy["bookmark_count"] as? Int) ?? 0
        
        // Impression / View Count extraction (Twitter GraphQL result["views"] or legacy["ext_views"])
        var viewCount: Int? = nil
        let viewsDict = (result["views"] as? [String: Any]) ?? (legacy["ext_views"] as? [String: Any]) ?? (result["ext_views"] as? [String: Any])
        if let countStr = viewsDict?["count"] as? String, let c = Int(countStr) {
            viewCount = c
        } else if let countInt = viewsDict?["count"] as? Int {
            viewCount = countInt
        } else if let countNum = viewsDict?["count"] as? NSNumber {
            viewCount = countNum.intValue
        }
        
        // Quoted tweet extraction
        var quotedTweet: Tweet? = nil
        if parseQuoted,
           let quotedObj = (result["quoted_status_result"] as? [String: Any]) ?? (legacy["quoted_status_result"] as? [String: Any]),
           let quotedRaw = quotedObj["result"] as? [String: Any] {
            quotedTweet = parseGraphQLTweetResult(quotedRaw, dateFormatter: dateFormatter, parseQuoted: false)
        }
        
        let inReplyToScreenName = legacy["in_reply_to_screen_name"] as? String
        let inReplyToStatusId = (legacy["in_reply_to_status_id_str"] as? String) ?? (legacy["in_reply_to_status_id"] as? NSNumber)?.stringValue
        
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
            retweetedBy: retweetedBy,
            isFavorited: isFavorited,
            isRetweeted: isRetweeted,
            isBookmarked: isBookmarked,
            bookmarkCount: bookmarkCount,
            viewCount: viewCount,
            quotedTweet: quotedTweet.map { QuotedTweetBox(tweet: $0) },
            inReplyToScreenName: inReplyToScreenName,
            inReplyToStatusId: inReplyToStatusId,
            links: Self.parseLinks(legacy["entities"] as? [String: Any])
        )
    }
    
    // A GraphQL user "result" object (tweet authors, profiles)
    static func parseUser(_ userResult: [String: Any]) -> TweetUser {
        let ucore = (userResult["core"] as? [String: Any]) ?? [:]
        let ulegacy = (userResult["legacy"] as? [String: Any]) ?? [:]
        let uavatar = (userResult["avatar"] as? [String: Any]) ?? [:]
        // Newer payloads leave user "legacy" empty and move counts/banner into their own objects
        let relationshipCounts = (userResult["relationship_counts"] as? [String: Any]) ?? [:]
        let rawAvatar = (uavatar["image_url"] as? String) ?? (ulegacy["profile_image_url_https"] as? String)
        
        return TweetUser(
            id: (userResult["rest_id"] as? String) ?? (userResult["id"] as? String) ?? "",
            name: (ucore["name"] as? String) ?? (ulegacy["name"] as? String) ?? "User",
            screenName: (ucore["screen_name"] as? String) ?? (ulegacy["screen_name"] as? String) ?? "",
            avatarUrl: rawAvatar?.replacingOccurrences(of: "_normal", with: "_bigger"),
            isVerified: (userResult["is_blue_verified"] as? Bool) ?? (ulegacy["verified"] as? Bool) ?? false,
            bio: (ulegacy["description"] as? String) ?? ((userResult["profile_bio"] as? [String: Any])?["description"] as? String),
            followersCount: (relationshipCounts["followers"] as? Int) ?? (ulegacy["followers_count"] as? Int),
            followingCount: (relationshipCounts["following"] as? Int) ?? (ulegacy["friends_count"] as? Int),
            bannerUrl: ((userResult["banner"] as? [String: Any])?["image_url"] as? String) ?? (ulegacy["profile_banner_url"] as? String),
            location: ((userResult["location"] as? [String: Any])?["location"] as? String) ?? (ulegacy["location"] as? String),
            bioLinks: parseLinks(
                (((userResult["profile_bio"] as? [String: Any])?["entities"] as? [String: Any])?["description"] as? [String: Any])
                    ?? ((ulegacy["entities"] as? [String: Any])?["description"] as? [String: Any])
            )
        )
    }
    
    // URL entities (t.co → expanded / display URL) from a tweet's legacy "entities"
    static func parseLinks(_ entities: [String: Any]?) -> [TweetLink] {
        let urls = (entities?["urls"] as? [[String: Any]]) ?? []
        return urls.compactMap { u in
            guard let url = u["url"] as? String, let expanded = u["expanded_url"] as? String else { return nil }
            return TweetLink(url: url, expandedUrl: expanded, displayUrl: (u["display_url"] as? String) ?? expanded)
        }
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
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
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
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
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
            createdAt: createdAt,
            iconId: iconId.isEmpty ? nil : iconId
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
            isVerified: isVerified,
            bio: userObj["description"] as? String,
            followersCount: userObj["followers_count"] as? Int,
            followingCount: userObj["friends_count"] as? Int,
            bannerUrl: userObj["profile_banner_url"] as? String,
            location: userObj["location"] as? String
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
                    
                    var videoInfo: TweetVideoInfo? = nil
                    if let vInfo = m["video_info"] as? [String: Any] {
                        let durationMillis = vInfo["duration_millis"] as? Int
                        let ar = vInfo["aspect_ratio"] as? [Int]
                        var variants: [TweetVideoVariant] = []
                        if let vList = vInfo["variants"] as? [[String: Any]] {
                            for v in vList {
                                if let cType = v["content_type"] as? String,
                                   let vUrl = v["url"] as? String {
                                    let br = v["bitrate"] as? Int
                                    variants.append(TweetVideoVariant(contentType: cType, url: vUrl, bitrate: br))
                                }
                            }
                        }
                        videoInfo = TweetVideoInfo(durationMillis: durationMillis, aspectRatio: ar, variants: variants)
                    }
                    
                    mediaList.append(TweetMedia(
                        id: mId,
                        type: mType,
                        mediaUrl: mUrl,
                        previewUrl: mUrl,
                        width: width,
                        height: height,
                        videoInfo: videoInfo
                    ))
                }
            }
        }
        
        let replyCount = (tweetObj["reply_count"] as? Int) ?? 0
        let retweetCount = (tweetObj["retweet_count"] as? Int) ?? 0
        let favoriteCount = (tweetObj["favorite_count"] as? Int) ?? 0
        let isFavorited = (tweetObj["favorited"] as? Bool) ?? ((tweetObj["favorited"] as? NSNumber)?.boolValue ?? false)
        let isRetweeted = (tweetObj["retweeted"] as? Bool) ?? ((tweetObj["retweeted"] as? NSNumber)?.boolValue ?? false)
        let isBookmarked = (tweetObj["bookmarked"] as? Bool) ?? ((tweetObj["bookmarked"] as? NSNumber)?.boolValue ?? false)
        let bookmarkCount = (tweetObj["bookmark_count"] as? Int) ?? 0
        
        var viewCount: Int? = nil
        if let extViews = tweetObj["ext_views"] as? [String: Any] {
            if let countStr = extViews["count"] as? String, let c = Int(countStr) {
                viewCount = c
            } else if let countInt = extViews["count"] as? Int {
                viewCount = countInt
            }
        }
        
        let inReplyToScreenName = tweetObj["in_reply_to_screen_name"] as? String
        let inReplyToStatusId = (tweetObj["in_reply_to_status_id_str"] as? String) ?? (tweetObj["in_reply_to_status_id"] as? NSNumber)?.stringValue
        
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
            retweetedBy: retweetedBy,
            isFavorited: isFavorited,
            isRetweeted: isRetweeted,
            isBookmarked: isBookmarked,
            bookmarkCount: bookmarkCount,
            viewCount: viewCount,
            quotedTweet: nil,
            inReplyToScreenName: inReplyToScreenName,
            inReplyToStatusId: inReplyToStatusId,
            links: Self.parseLinks(tweetObj["entities"] as? [String: Any])
        )
    }
    
    // MARK: - Fetch Official User Lists
    func fetchUserLists(completion: @escaping (Result<[TwitterList], APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials() else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let queryId = "EJr344tsMZZpEwjeaYvk-g"
        let variables: [String: Any] = ["count": 100]
        let features: [String: Any] = [
            "responsive_web_graphql_timeline_navigation_enabled": true
        ]
        
        guard let varData = try? JSONSerialization.data(withJSONObject: variables),
              let featData = try? JSONSerialization.data(withJSONObject: features),
              let varStr = String(data: varData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let featStr = String(data: featData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let gqlURL = URL(string: "https://x.com/i/api/graphql/\(queryId)/ListsManagementPageTimeline?variables=\(varStr)&features=\(featStr)") else {
            self.fetchUserListsREST(creds: creds, completion: completion)
            return
        }
        
        var request = URLRequest(url: gqlURL)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data,
               let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let lists = self.parseListsManagementTimeline(data: data)
                if !lists.isEmpty {
                    completion(.success(lists))
                    return
                }
            }
            // Fallback to REST /1.1/lists/list.json
            self.fetchUserListsREST(creds: creds, completion: completion)
        }
        task.resume()
    }
    
    private func fetchUserListsREST(creds: AuthCredentials, completion: @escaping (Result<[TwitterList], APIError>) -> Void) {
        guard let restURL = URL(string: "https://api.x.com/1.1/lists/list.json?reverse=true") else {
            completion(.failure(.parseError))
            return
        }
        
        var request = URLRequest(url: restURL)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(.invalidResponse))
                return
            }
            let lists = self.parseRESTUserLists(data: data)
            completion(.success(lists))
        }
        task.resume()
    }
    
    func parseListsManagementTimeline(data: Data) -> [TwitterList] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let viewer = d["viewer"] as? [String: Any],
              let lmt = viewer["list_management_timeline"] as? [String: Any],
              let timeline = lmt["timeline"] as? [String: Any],
              let instructions = timeline["instructions"] as? [[String: Any]] else {
            return []
        }
        
        var lists: [TwitterList] = []
        var seenIds = Set<String>()
        
        for inst in instructions {
            guard let entries = inst["entries"] as? [[String: Any]] else { continue }
            for entry in entries {
                let eid = entry["entryId"] as? String ?? ""
                let isPinned = eid.hasPrefix("pinned-list-module")
                let isOwnedOrSub = eid.hasPrefix("owned-subscribed-list-module")
                
                if isPinned || isOwnedOrSub {
                    guard let content = entry["content"] as? [String: Any],
                          let items = content["items"] as? [[String: Any]] else { continue }
                    for subItem in items {
                        guard let itm = subItem["item"] as? [String: Any],
                              let ic = itm["itemContent"] as? [String: Any],
                              let l = ic["list"] as? [String: Any] else { continue }
                        
                        let id = (l["id_str"] as? String) ?? (l["id"] as? Int64).map { String($0) } ?? ""
                        let name = (l["name"] as? String) ?? ""
                        guard !id.isEmpty, !name.isEmpty, !seenIds.contains(id) else { continue }
                        seenIds.insert(id)
                        
                        let desc = l["description"] as? String
                        let memberCount = (l["member_count"] as? Int) ?? 0
                        let subscriberCount = (l["subscriber_count"] as? Int) ?? 0
                        let mode = l["mode"] as? String ?? "Public"
                        let isPrivate = mode.lowercased() == "private"
                        
                        var ownerName: String?
                        var ownerHandle: String?
                        if let userRes = l["user_results"] as? [String: Any],
                           let res = userRes["result"] as? [String: Any] {
                            let core = (res["core"] as? [String: Any]) ?? [:]
                            let legacy = (res["legacy"] as? [String: Any]) ?? [:]
                            ownerName = (legacy["name"] as? String) ?? (core["name"] as? String)
                            ownerHandle = (legacy["screen_name"] as? String) ?? (core["screen_name"] as? String)
                        }
                        
                        var bannerUrl: String?
                        if let bannerMedia = l["default_banner_media"] as? [String: Any] {
                            bannerUrl = bannerMedia["media_url_https"] as? String
                        }
                        
                        lists.append(TwitterList(
                            id: id,
                            name: name,
                            description: desc,
                            memberCount: memberCount,
                            subscriberCount: subscriberCount,
                            isPrivate: isPrivate,
                            isPinned: isPinned,
                            bannerUrl: bannerUrl,
                            ownerName: ownerName,
                            ownerHandle: ownerHandle
                        ))
                    }
                }
            }
        }
        return lists
    }
    
    func parseRESTUserLists(data: Data) -> [TwitterList] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { item -> TwitterList? in
            guard let id = (item["id_str"] as? String) ?? (item["id"] as? Int64).map({ String($0) }),
                  let name = item["name"] as? String, !id.isEmpty, !name.isEmpty else {
                return nil
            }
            let desc = item["description"] as? String
            let memberCount = item["member_count"] as? Int ?? 0
            let subscriberCount = item["subscriber_count"] as? Int ?? 0
            let mode = item["mode"] as? String ?? "public"
            let isPrivate = mode.lowercased() == "private"
            
            var ownerName: String?
            var ownerHandle: String?
            if let user = item["user"] as? [String: Any] {
                ownerName = user["name"] as? String
                ownerHandle = user["screen_name"] as? String
            }
            
            return TwitterList(
                id: id,
                name: name,
                description: desc,
                memberCount: memberCount,
                subscriberCount: subscriberCount,
                isPrivate: isPrivate,
                isPinned: false,
                bannerUrl: nil,
                ownerName: ownerName,
                ownerHandle: ownerHandle
            )
        }
    }
    
    // MARK: - Tweet Engagement Mutations
    
    private func performGraphQLMutation(
        endpoint: String,
        body: [String: Any],
        referer: String = "https://x.com/home",
        successCheck: @escaping ([String: Any]) -> Bool,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        guard let url = URL(string: endpoint) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "referer")
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.parseError))
            return
        }
        request.httpBody = httpBody
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            guard (200...299).contains(httpResponse.statusCode), let data = data else {
                completion(.failure(.serverError("HTTP \(httpResponse.statusCode)")))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                    let msg = errors.compactMap { $0["message"] as? String }.joined(separator: ", ")
                    completion(.failure(.serverError(msg.isEmpty ? "Action rejected by server" : msg)))
                    return
                }
                guard let dataObj = json["data"] as? [String: Any], successCheck(dataObj) else {
                    completion(.failure(.serverError("Unexpected server response")))
                    return
                }
                completion(.success(()))
            } catch {
                completion(.failure(.parseError))
            }
        }
        task.resume()
    }
    
    /// Like a tweet
    func favoriteTweet(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "lI07N6Otwv1PhnEgXILM7A"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/FavoriteTweet"
        let body: [String: Any] = [
            "variables": ["tweet_id": id],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { ($0["favorite_tweet"] as? String) == "Done" },
            completion: completion
        )
    }
    
    /// Remove like from a tweet
    func unfavoriteTweet(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "ZYKSe-w7KEslx3JhSIk5LA"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/UnfavoriteTweet"
        let body: [String: Any] = [
            "variables": ["tweet_id": id],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { ($0["unfavorite_tweet"] as? String) == "Done" },
            completion: completion
        )
    }
    
    /// Retweet a tweet
    func retweet(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "mbRO74GrOvSfRcJnlMapnQ"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/CreateRetweet"
        let body: [String: Any] = [
            "variables": ["tweet_id": id, "dark_request": false],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { $0["create_retweet"] != nil },
            completion: completion
        )
    }
    
    /// Remove retweet from a tweet
    func unretweet(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "ZyZigVsNiFO6v1dEks1eWg"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/DeleteRetweet"
        let body: [String: Any] = [
            "variables": ["source_tweet_id": id, "tweet_id": id, "dark_request": false],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { $0["unretweet"] != nil },
            completion: completion
        )
    }
    
    /// Bookmark a tweet
    func bookmark(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "aoDbu3RHznuiSkQ9aNM67Q"
        // Note: Production Twitter maps CreateBookmark directly to the query ID without action name suffix
        let endpoint = "https://x.com/i/api/graphql/\(qid)"
        let body: [String: Any] = [
            "variables": ["tweet_id": id],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { ($0["tweet_bookmark_put"] as? String) == "Done" },
            completion: completion
        )
    }
    
    /// Remove bookmark from a tweet
    func unbookmark(id: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let qid = "Wlmlj2-xzyS1GN3a6cj-mQ"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/DeleteBookmark"
        let body: [String: Any] = [
            "variables": ["tweet_id": id],
            "queryId": qid
        ]
        performGraphQLMutation(
            endpoint: endpoint,
            body: body,
            successCheck: { ($0["tweet_bookmark_delete"] as? String) == "Done" },
            completion: completion
        )
    }
    
    /// Reply to a tweet
    func reply(to tweetId: String, text: String, completion: @escaping (Result<String, APIError>) -> Void) {
        createTweet(text: text, replyToTweetId: tweetId, attachmentUrl: nil, completion: completion)
    }
    
    /// Create a new tweet (standalone post, reply, or quote post)
    func createTweet(
        text: String,
        replyToTweetId: String? = nil,
        attachmentUrl: String? = nil,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        let qid = "5CVj-J0FZWyGgJpcjeBJEA"
        let endpoint = "https://x.com/i/api/graphql/\(qid)/CreateTweet"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://x.com/compose/post", forHTTPHeaderField: "referer")
        
        let features: [String: Any] = [
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": false,
            "responsive_web_jetfuel_frame": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_enhance_cards_enabled": false
        ]
        
        var variables: [String: Any] = [
            "tweet_text": text,
            "dark_request": false,
            "media": [
                "media_entities": [],
                "possibly_sensitive": false
            ],
            "semantic_annotation_ids": []
        ]
        
        if let replyTo = replyToTweetId, !replyTo.isEmpty {
            variables["reply"] = [
                "in_reply_to_tweet_id": replyTo,
                "exclude_reply_user_ids": []
            ]
        }
        
        if let attach = attachmentUrl, !attach.isEmpty {
            variables["attachment_url"] = attach
        }
        
        let body: [String: Any] = [
            "variables": variables,
            "features": features,
            "queryId": qid
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.parseError))
            return
        }
        request.httpBody = httpBody
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            guard (200...299).contains(httpResponse.statusCode), let data = data else {
                completion(.failure(.serverError("HTTP \(httpResponse.statusCode)")))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                    let msg = errors.compactMap { $0["message"] as? String }.joined(separator: ", ")
                    completion(.failure(.serverError(msg.isEmpty ? "Reply failed" : msg)))
                    return
                }
                guard let dataObj = json["data"] as? [String: Any],
                      let createTweet = dataObj["create_tweet"] as? [String: Any],
                      let tweetResults = createTweet["tweet_results"] as? [String: Any],
                      let result = tweetResults["result"] as? [String: Any],
                      let restId = result["rest_id"] as? String ?? (result["legacy"] as? [String: Any])?["id_str"] as? String else {
                    completion(.failure(.serverError("Tweet created but no ID returned")))
                    return
                }
                completion(.success(restId))
            } catch {
                completion(.failure(.parseError))
            }
        }
        task.resume()
    }
    
    // MARK: - Fetch Tweet Detail & Thread Conversation
    func fetchTweetDetail(
        tweetId: String,
        cursor: String? = nil,
        completion: @escaping (Result<(focalTweet: Tweet?, ancestors: [Tweet], replies: [Tweet], bottomCursor: String?), APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        
        let qid = "gJoREC4Bspo4kJ0ax9C3sQ"
        
        var variables: [String: Any] = [
            "focalTweetId": tweetId,
            "with_rux_injections": false,
            "rankingMode": "Relevance",
            "includePromotedContent": ThemeManager.shared.showPromotedPosts,
            "withCommunity": true,
            "withQuickPromoteEligibility": false,
            "withBirdwatchNotes": true,
            "withVoice": true
        ]
        if let cursor = cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }
        
        let features: [String: Any] = [
            "rweb_video_screen_enabled": true,
            "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": false,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "articles_preview_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reached_appeal_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "responsive_web_enhance_cards_enabled": false
        ]
        
        guard let varData = try? JSONSerialization.data(withJSONObject: variables),
              let varStr = String(data: varData, encoding: .utf8),
              let featData = try? JSONSerialization.data(withJSONObject: features),
              let featStr = String(data: featData, encoding: .utf8) else {
            completion(.failure(.parseError))
            return
        }
        
        var comp = URLComponents(string: "https://x.com/i/api/graphql/\(qid)/TweetDetail")!
        comp.queryItems = [
            URLQueryItem(name: "variables", value: varStr),
            URLQueryItem(name: "features", value: featStr)
        ]
        
        guard let url = comp.url else {
            completion(.failure(.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(bearerToken, forHTTPHeaderField: "authorization")
        request.setValue(creds.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(creds.cookieHeaderString, forHTTPHeaderField: "cookie")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(clientLanguageHeader, forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://x.com/", forHTTPHeaderField: "referer")
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            guard (200...299).contains(httpResponse.statusCode), let data = data else {
                completion(.failure(.serverError("HTTP \(httpResponse.statusCode)")))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.parseError))
                    return
                }
                guard let dataObj = json["data"] as? [String: Any],
                      let threadedConv = dataObj["threaded_conversation_with_injections_v2"] as? [String: Any],
                      let instructions = threadedConv["instructions"] as? [[String: Any]] else {
                    completion(.failure(.parseError))
                    return
                }
                
                var focalTweet: Tweet?
                var ancestors: [Tweet] = []
                var replies: [Tweet] = []
                var bottomCursor: String?
                
                for inst in instructions {
                    guard let type = inst["type"] as? String else { continue }
                    if type == "TimelineAddEntries" {
                        let entries = (inst["entries"] as? [[String: Any]]) ?? []
                        for entry in entries {
                            let entryId = (entry["entryId"] as? String) ?? ""
                            let content = (entry["content"] as? [String: Any]) ?? [:]
                            let entryType = (content["entryType"] as? String) ?? ""
                            
                            if entryType == "TimelineTimelineItem" {
                                if let tweet = self.buildGraphQLTweet(entry: entry, dateFormatter: dateFormatter) {
                                    if tweet.id == tweetId {
                                        focalTweet = tweet
                                    } else if focalTweet == nil {
                                        ancestors.append(tweet)
                                    } else {
                                        replies.append(tweet)
                                    }
                                }
                            } else if entryType == "TimelineTimelineModule" && entryId.hasPrefix("conversationthread-") {
                                let items = (content["items"] as? [[String: Any]]) ?? []
                                for it in items {
                                    guard let itemObj = it["item"] as? [String: Any],
                                          let itemContent = itemObj["itemContent"] as? [String: Any],
                                          let tweetResults = itemContent["tweet_results"] as? [String: Any],
                                          let res = tweetResults["result"] as? [String: Any] else {
                                        continue
                                    }
                                    let itemEntryId = (it["entryId"] as? String) ?? ""
                                    let isPromoted = self.isPromotedEntry(entryId: itemEntryId, itemContent: itemContent, itemObj: itemObj, resultObj: res)
                                    if isPromoted && !ThemeManager.shared.showPromotedPosts {
                                        continue
                                    }
                                    if var replyTweet = self.parseGraphQLTweetResult(res, dateFormatter: dateFormatter) {
                                        if isPromoted {
                                            replyTweet.isPromoted = true
                                        }
                                        replies.append(replyTweet)
                                    }
                                }
                            } else if entryType == "TimelineTimelineCursor" || entryId.hasPrefix("cursor-bottom") {
                                if let cursorType = content["cursorType"] as? String, cursorType == "Bottom" {
                                    bottomCursor = content["value"] as? String
                                } else if entryId.hasPrefix("cursor-bottom") {
                                    bottomCursor = content["value"] as? String
                                }
                            }
                        }
                    }
                }
                
                completion(.success((focalTweet, ancestors, replies, bottomCursor)))
            } catch {
                completion(.failure(.parseError))
            }
        }
        task.resume()
    }
    
    func fetchTweetDetail(tweetId: String, cursor: String? = nil) async throws -> (focalTweet: Tweet?, ancestors: [Tweet], replies: [Tweet], bottomCursor: String?) {
        try await withCheckedThrowingContinuation { continuation in
            fetchTweetDetail(tweetId: tweetId, cursor: cursor) { result in
                continuation.resume(with: result)
            }
        }
    }
}
