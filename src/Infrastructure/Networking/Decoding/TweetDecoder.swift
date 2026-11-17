//
//  TweetDecoder.swift
//  Tweetintosh
//
//  Shared decoding of X's post and user payloads. Feature endpoints differ in the timeline envelopes they read;
//  the post, user, link and article objects inside them are the same.
//

import Foundation

extension APIClient {
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
        var originalId: String?

        // Handle Retweet in GraphQL
        if let rtResult = legacy["retweeted_status_result"] as? [String: Any],
           var original = rtResult["result"] as? [String: Any] {
            isRetweet = true
            if let innerRt = original["tweet"] as? [String: Any] {
                original = innerRt
            }
            originalId = original["rest_id"] as? String
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

        var tweet = Tweet(
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
            links: Self.parseLinks(legacy["entities"] as? [String: Any]),
            article: Self.parseArticlePreview(result["article"] as? [String: Any])
        )
        tweet.originalId = originalId
        // A long post's whole text, which X leaves out of "legacy"
        if let note = ((result["note_tweet"] as? [String: Any])?["note_tweet_results"] as? [String: Any])?["result"] as? [String: Any],
           let noteText = note["text"] as? String, !noteText.isEmpty {
            tweet.setLongText(noteText, links: Self.parseLinks(note["entity_set"] as? [String: Any]))
        }
        return tweet
    }

    // The article attached to a post: its title, opening lines and cover. The text itself comes from fetchArticle.
    static func parseArticlePreview(_ article: [String: Any]?) -> TweetArticle? {
        guard let entity = (article?["article_results"] as? [String: Any])?["result"] as? [String: Any],
              let id = entity["rest_id"] as? String,
              let title = entity["title"] as? String else { return nil }
        let cover = ((entity["cover_media"] as? [String: Any])?["media_info"] as? [String: Any])?["original_img_url"] as? String
        return TweetArticle(id: id, title: title, previewText: (entity["preview_text"] as? String) ?? "", coverUrl: cover)
    }

    // A GraphQL user "result" object (tweet authors, profiles)
    static func parseUser(_ userResult: [String: Any]) -> TweetUser {
        let ucore = (userResult["core"] as? [String: Any]) ?? [:]
        let ulegacy = (userResult["legacy"] as? [String: Any]) ?? [:]
        let uavatar = (userResult["avatar"] as? [String: Any]) ?? [:]
        // Newer payloads leave user "legacy" empty and move counts/banner into their own objects
        let relationshipCounts = (userResult["relationship_counts"] as? [String: Any]) ?? [:]
        let perspectives = (userResult["relationship_perspectives"] as? [String: Any]) ?? [:]
        let rawAvatar = (uavatar["image_url"] as? String) ?? (ulegacy["profile_image_url_https"] as? String)

        let userId = (userResult["rest_id"] as? String) ?? (userResult["id"] as? String) ?? ""
        if perspectives["blocked_by"] as? Bool == true {
            BlockedByRegistry.shared.insert(userId)
        }

        return TweetUser(
            id: userId,
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
            ),
            blockedBy: perspectives["blocked_by"] as? Bool,
            blocking: perspectives["blocking"] as? Bool
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
}
