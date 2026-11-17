//
//  SearchAPI.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Search: X's SearchTimeline operation for posts (Top, Latest) and people.
//

import Foundation

enum SearchTab: String, CaseIterable, Identifiable {
    case top
    case latest
    case people

    var id: String { rawValue }
    
    // ⌥Q / ⌥W / ⌥E, the same keys the Notifications filters use
    var shortcutKey: String {
        switch self {
        case .top: return "⌥Q"
        case .latest: return "⌥W"
        case .people: return "⌥E"
        }
    }
    
    static func forKeyCode(_ keyCode: UInt16) -> SearchTab? {
        switch keyCode {
        case 12: return .top
        case 13: return .latest
        case 14: return .people
        default: return nil
        }
    }
    
    // X's name for the result set
    var product: String {
        switch self {
        case .top: return "Top"
        case .latest: return "Latest"
        case .people: return "People"
        }
    }
}

struct SearchPage {
    var tweets: [Tweet]
    var users: [TweetUser]
    var bottomCursor: String?
}

extension APIClient {
    func fetchSearch(
        query: String,
        tab: SearchTab,
        cursor: String?,
        completion: @escaping (Result<SearchPage, APIError>) -> Void
    ) {
        var variables: [String: Any] = [
            "rawQuery": query,
            "count": 20,
            "querySource": "typed_query",
            "product": tab.product
        ]
        if let cursor = cursor { variables["cursor"] = cursor }

        graphQLGet(operation: "SearchTimeline", variables: variables, usePost: true) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                completion(.success(self.parseSearch(json)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseSearch(_ json: [String: Any]) -> SearchPage {
        let timeline = (((json["data"] as? [String: Any])?["search_by_raw_query"] as? [String: Any])?["search_timeline"] as? [String: Any])?["timeline"] as? [String: Any]
        let instructions = (timeline?["instructions"] as? [[String: Any]]) ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"

        var tweets: [Tweet] = []
        var users: [TweetUser] = []
        var seen = Set<String>()
        var bottomCursor: String?

        func addItem(_ itemContent: [String: Any]?) {
            guard let itemContent = itemContent else { return }
            // Ads are skipped unless promoted posts are switched on in Settings
            if itemContent["promotedMetadata"] != nil && !ThemeManager.shared.showPromotedPosts { return }

            if let result = (itemContent["tweet_results"] as? [String: Any])?["result"] as? [String: Any],
               let tweet = parseGraphQLTweetResult(result, dateFormatter: formatter),
               seen.insert("t-" + tweet.id).inserted {
                tweets.append(tweet)
            } else if let result = (itemContent["user_results"] as? [String: Any])?["result"] as? [String: Any] {
                let user = Self.parseUser(result)
                if !user.id.isEmpty, seen.insert("u-" + user.id).inserted {
                    users.append(user)
                }
            }
        }

        for inst in instructions {
            switch inst["type"] as? String {
            case "TimelineAddEntries":
                for entry in (inst["entries"] as? [[String: Any]]) ?? [] {
                    let content = (entry["content"] as? [String: Any]) ?? [:]
                    switch content["entryType"] as? String {
                    case "TimelineTimelineItem":
                        addItem(content["itemContent"] as? [String: Any])
                    case "TimelineTimelineModule":
                        for item in (content["items"] as? [[String: Any]]) ?? [] {
                            addItem((item["item"] as? [String: Any])?["itemContent"] as? [String: Any])
                        }
                    case "TimelineTimelineCursor":
                        if (content["cursorType"] as? String) == "Bottom" {
                            bottomCursor = content["value"] as? String
                        }
                    default:
                        break
                    }
                }
            case "TimelineReplaceEntry":
                // Later pages hand over the next cursor by replacing the previous one
                let content = ((inst["entry"] as? [String: Any])?["content"] as? [String: Any]) ?? [:]
                if (content["cursorType"] as? String) == "Bottom" {
                    bottomCursor = content["value"] as? String
                }
            default:
                break
            }
        }
        return SearchPage(tweets: tweets, users: users, bottomCursor: bottomCursor)
    }
}
