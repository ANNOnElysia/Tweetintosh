//
//  ProfileAPI.swift
//  Tweetintosh - Headless Data-driven Client
//
//  User profiles: profile lookup, the Posts / Replies / Media timelines, and follow / unfollow.
//

import Foundation

// MARK: - Models

struct UserProfile {
    var user: TweetUser
    var websiteUrl: URL?
    var websiteDisplay: String?
    var joinedAt: Date?
    var postsCount: Int?
    var isFollowing: Bool
    var isProtected: Bool
    var isMuting: Bool = false
    var isBlocking: Bool = false
    // They follow the signed-in account
    var followsYou: Bool = false
}

// One of the signed-in account's own lists, and whether the person being looked at is on it
struct OwnedList: Identifiable, Equatable {
    let id: String
    let name: String
    var isMember: Bool
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

// MARK: - Requests

extension APIClient {
    // MARK: Bookmarks

    // The signed-in account's bookmarks, newest first, a page at a time
    func fetchBookmarks(
        cursor: String?,
        completion: @escaping (Result<(tweets: [Tweet], topCursor: String?, bottomCursor: String?), APIError>) -> Void
    ) {
        var variables: [String: Any] = ["count": 20, "includePromotedContent": false]
        if let cursor = cursor { variables["cursor"] = cursor }
        graphQLGet(operation: "Bookmarks", variables: variables,
                   extraFeatures: ["graphql_timeline_v2_bookmark_timeline": true]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json): completion(.success(self.parseBookmarks(json)))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    private func parseBookmarks(_ json: [String: Any]) -> (tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
        let data = json["data"] as? [String: Any]
        let timeline = (data?["bookmark_timeline_v2"] as? [String: Any]) ?? (data?["bookmark_timeline"] as? [String: Any])
        let instructions = ((timeline?["timeline"] as? [String: Any])?["instructions"] as? [[String: Any]]) ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"

        var tweets: [Tweet] = []
        var seen = Set<String>()
        var topCursor: String?
        var bottomCursor: String?
        for instruction in instructions {
            let entries = (instruction["entries"] as? [[String: Any]])
                ?? ((instruction["entry"] as? [String: Any]).map { [$0] } ?? [])
            for entry in entries {
                let content = (entry["content"] as? [String: Any]) ?? [:]
                if let cursorType = content["cursorType"] as? String, let value = content["value"] as? String {
                    if cursorType == "Bottom" { bottomCursor = value }
                    if cursorType == "Top" { topCursor = value }
                    continue
                }
                guard let result = ((content["itemContent"] as? [String: Any])?["tweet_results"] as? [String: Any])?["result"] as? [String: Any],
                      let tweet = parseGraphQLTweetResult(result, dateFormatter: formatter),
                      !seen.contains(tweet.id) else { continue }
                seen.insert(tweet.id)
                tweets.append(tweet)
            }
        }
        return (tweets, topCursor, bottomCursor)
    }

    // MARK: People who liked or reposted a post

    func fetchTweetUsers(
        kind: TweetUsersKind,
        tweetId: String,
        cursor: String? = nil,
        completion: @escaping (Result<(users: [TweetUser], bottomCursor: String?), APIError>) -> Void
    ) {
        // A list that fell back to the REST endpoint keeps paging there
        if let cursor = cursor, cursor.hasPrefix(Self.restCursorPrefix) {
            fetchFollowListREST(kind, userId: tweetId, cursor: String(cursor.dropFirst(Self.restCursorPrefix.count)), completion: completion)
            return
        }
        var variables: [String: Any] = [kind.subjectKey: tweetId, "count": 40, "includePromotedContent": kind.subjectKey == "tweetId"]
        if let cursor = cursor { variables["cursor"] = cursor }
        graphQLGet(operation: kind.operation, variables: variables) { [weak self] result in
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
                // X answers 404 to the Followers query id its own web client lists; the older REST lists still work
                // with the same session, so following and followers fall back to them
                if cursor == nil, kind == .following || kind == .followers, let self = self {
                    self.fetchFollowListREST(kind, userId: tweetId, cursor: "-1", completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    private static let restCursorPrefix = "rest:"

    private func fetchFollowListREST(
        _ kind: TweetUsersKind,
        userId: String,
        cursor: String,
        completion: @escaping (Result<(users: [TweetUser], bottomCursor: String?), APIError>) -> Void
    ) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        let path = kind == .followers ? "followers" : "friends"
        var components = URLComponents(string: "https://x.com/i/api/1.1/\(path)/list.json")!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "count", value: "40"),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "skip_status", value: "true"),
            URLQueryItem(name: "include_user_entities", value: "true")
        ]
        guard let url = components.url else { return completion(.failure(.invalidResponse)) }
        session.dataTask(with: authorizedRequest(url, method: "GET", creds: creds)) { data, response, error in
            if let error = error { return completion(.failure(.networkError(error))) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                graphQLLog.error("\(path, privacy: .public)/list.json refused: HTTP \(status, privacy: .public)")
                return completion(.failure(.serverError(Self.errorMessage(from: data) ?? "HTTP \(status)")))
            }
            // A REST user is shaped like a GraphQL user's "legacy" object
            let users = ((json["users"] as? [[String: Any]]) ?? []).compactMap { raw -> TweetUser? in
                guard let id = raw["id_str"] as? String else { return nil }
                return Self.parseUser(["rest_id": id, "legacy": raw])
            }
            let next = json["next_cursor_str"] as? String
            completion(.success((users, (next == nil || next == "0") ? nil : Self.restCursorPrefix + next!)))
        }.resume()
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
            isProtected: ((userResult["privacy"] as? [String: Any])?["protected"] as? Bool) ?? (legacy["protected"] as? Bool) ?? false,
            isMuting: ((userResult["relationship_perspectives"] as? [String: Any])?["muting"] as? Bool) ?? (legacy["muting"] as? Bool) ?? false,
            isBlocking: ((userResult["relationship_perspectives"] as? [String: Any])?["blocking"] as? Bool) ?? (legacy["blocking"] as? Bool) ?? false,
            followsYou: ((userResult["relationship_perspectives"] as? [String: Any])?["followed_by"] as? Bool) ?? (legacy["followed_by"] as? Bool) ?? false
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

    // MARK: Lists

    // The account's own lists, not the ones it merely subscribes to: only an owner can add people
    func fetchOwnedLists(ownerId: String, targetUserId: String, completion: @escaping (Result<[OwnedList], APIError>) -> Void) {
        let variables: [String: Any] = ["userId": ownerId, "isListMemberTargetUserId": targetUserId, "count": 100]
        graphQLGet(operation: "ListOwnerships", variables: variables) { result in
            completion(result.map { json in
                var lists: [OwnedList] = []
                Self.collectOwnedLists(in: json, into: &lists)
                return lists
            })
        }
    }

    // Timeline responses nest their entries differently from one page to the next, so this looks for the lists
    // themselves rather than following one path
    private static func collectOwnedLists(in value: Any, into lists: inout [OwnedList]) {
        if let array = value as? [Any] {
            array.forEach { collectOwnedLists(in: $0, into: &lists) }
        } else if let dict = value as? [String: Any] {
            if let list = dict["list"] as? [String: Any], let id = list["id_str"] as? String, let name = list["name"] as? String,
               !lists.contains(where: { $0.id == id }) {
                lists.append(OwnedList(id: id, name: name, isMember: (list["is_member"] as? Bool) ?? false))
                return
            }
            dict.values.forEach { collectOwnedLists(in: $0, into: &lists) }
        }
    }

    func setListMember(_ member: Bool, listId: String, userId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let creds = CredentialsManager.shared.loadCredentials(), creds.isValid else {
            completion(.failure(.unauthenticated))
            return
        }
        let operation = member ? "ListAddMember" : "ListRemoveMember"

        func attempt(_ ids: [String]) {
            guard let id = ids.first else {
                completion(.failure(.serverError(LocalizationManager.shared.t("error_query_id_missing"))))
                return
            }
            let body: [String: Any] = [
                "variables": ["listId": listId, "userId": userId],
                "features": Self.graphQLFeatures,
                "queryId": id
            ]
            WebKitWriteChannel.shared.perform(path: "/i/api/graphql/\(id)/\(operation)", body: body) { result in
                switch result {
                case .success(let json) where (json["data"] as? [String: Any])?["list"] != nil:
                    GraphQLOperationIDs.shared.markWorking(id, for: operation)
                    completion(.success(()))
                case .failure(let error):
                    if case .refused = error { completion(.failure(error)) } else { attempt(Array(ids.dropFirst())) }
                case .success:
                    attempt(Array(ids.dropFirst()))
                }
            }
        }

        let known = GraphQLOperationIDs.shared.ids(for: operation)
        if known.isEmpty {
            GraphQLOperationIDs.shared.discover(using: self, creds: creds) {
                attempt(GraphQLOperationIDs.shared.ids(for: operation))
            }
        } else {
            attempt(known)
        }
    }

    // MARK: Edit Profile

    // The same endpoints and limits as X's own Edit profile sheet. Sent from inside x.com, like every other write.
    func updateProfile(name: String, bio: String, location: String, website: String,
                       completion: @escaping (Result<Void, APIError>) -> Void) {
        let fields = ["name": name, "description": bio, "location": location, "url": website]
        WebKitWriteChannel.shared.performForm(path: "/i/api/1.1/account/update_profile.json", fields: fields) { result in
            completion(result.map { _ in () })
        }
    }

    // JPEG data, already cropped and sized: 400×400 for the photo, 1500×500 for the header
    func updateProfileImage(_ jpeg: Data, completion: @escaping (Result<Void, APIError>) -> Void) {
        let fields = ["image": jpeg.base64EncodedString(), "skip_status": "1", "return_user": "true"]
        WebKitWriteChannel.shared.performForm(path: "/i/api/1.1/account/update_profile_image.json", fields: fields) { result in
            completion(result.map { _ in () })
        }
    }

    func updateProfileBanner(_ jpeg: Data, completion: @escaping (Result<Void, APIError>) -> Void) {
        let fields = ["banner": jpeg.base64EncodedString()]
        WebKitWriteChannel.shared.performForm(path: "/i/api/1.1/account/update_profile_banner.json", fields: fields) { result in
            completion(result.map { _ in () })
        }
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
// Which list of people to show: those who liked or reposted a post, or who an account follows or is followed by
enum TweetUsersKind: String {
    case likes, reposts, following, followers

    var operation: String {
        switch self {
        case .likes: return "Favoriters"
        case .reposts: return "Retweeters"
        case .following: return "Following"
        case .followers: return "Followers"
        }
    }

    // What the subject's id is called in the request: a post's for likes and reposts, an account's for the others
    var subjectKey: String {
        switch self {
        case .likes, .reposts: return "tweetId"
        case .following, .followers: return "userId"
        }
    }

    var titleKey: String {
        switch self {
        case .likes: return "liked_by"
        case .reposts: return "reposted_by"
        case .following: return "peek_following"
        case .followers: return "peek_followers"
        }
    }
}
