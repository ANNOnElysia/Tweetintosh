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
    
    // MARK: - Fetch Home Timeline
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
