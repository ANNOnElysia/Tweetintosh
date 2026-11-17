//
//  ImmersiveMediaAPI.swift
//  Tweetintosh
//
//  X's immersive video feed: the request X's own client makes and the batch it answers with.
//

import Foundation

extension APIClient {
    // The flags X's own client sends with ImmersiveMedia (captured 2026-11-08), laid over the shared set, which refuses a
    // request missing any flag the operation expects
    private static let immersiveMediaFeatures: [String: Any] = [
        "rweb_video_screen_enabled": false,
        "rweb_cashtags_enabled": true,
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "responsive_web_profile_redirect_enabled": true,
        "rweb_tipjar_consumption_enabled": false,
        "verified_phone_label_enabled": false,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "premium_content_api_read_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
        "responsive_web_grok_analyze_post_followups_enabled": true,
        "rweb_cashtags_composer_attachment_enabled": true,
        "responsive_web_jetfuel_frame": true,
        "rweb_sports_post_context_enabled": true,
        "x_elections_post_context_enabled": true,
        "responsive_web_grok_share_attachment_enabled": true,
        "responsive_web_grok_annotations_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "rweb_conversational_replies_downvote_enabled": false,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "content_disclosure_indicator_enabled": true,
        "content_disclosure_ai_generated_indicator_enabled": true,
        "responsive_web_grok_show_grok_translated_post": true,
        "responsive_web_grok_analysis_button_from_backend": true,
        "post_ctas_fetch_enabled": true,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": false,
        "responsive_web_nested_quote_preview_enabled": true,
        "responsive_web_grok_image_annotation_enabled": true,
        "responsive_web_grok_imagine_annotation_enabled": true,
        "responsive_web_made_on_x_label_enabled": false,
        "responsive_web_grok_community_note_auto_translation_is_enabled": true,
        "responsive_web_enhance_cards_enabled": false
    ]

    // One batch of recommended videos, starting from a video post. X's own client never sends the cursors this returns:
    // for more, it asks again with the same post, and each answer is a new batch that repeats none of the earlier ones.
    // The starting post comes back only in the first batch.
    func fetchImmersiveMedia(
        pinnedPostId: String,
        authorScreenName: String,
        completion: @escaping (Result<[Tweet], APIError>) -> Void
    ) {
        // X's client asks for ads too; this doesn't
        let variables: [String: Any] = [
            "pinned_tweet_id": pinnedPostId,
            "page_name": authorScreenName,
            "includePromotedContent": false
        ]
        graphQLGet(operation: "ImmersiveMedia", variables: variables,
                   extraFeatures: Self.immersiveMediaFeatures) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json): completion(.success(self.parseImmersiveMedia(json)))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    private func parseImmersiveMedia(_ json: [String: Any]) -> [Tweet] {
        let timeline = ((json["data"] as? [String: Any])?["immersiveMedia"] as? [String: Any])?["timeline"] as? [String: Any]
        let instructions = (timeline?["instructions"] as? [[String: Any]]) ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"

        var posts: [Tweet] = []
        var seen = Set<String>()
        for instruction in instructions {
            for entry in (instruction["entries"] as? [[String: Any]]) ?? [] {
                // Ads are asked not to come, and are dropped anyway if they do
                let entryId = (entry["entryId"] as? String) ?? ""
                guard entryId.hasPrefix("tweet-"),
                      let content = entry["content"] as? [String: Any],
                      let itemContent = content["itemContent"] as? [String: Any],
                      itemContent["promotedMetadata"] == nil,
                      !((itemContent["itemContentType"] as? String) ?? "").contains("ImmersiveAd"),
                      let result = (itemContent["tweet_results"] as? [String: Any])?["result"] as? [String: Any],
                      result["promotedMetadata"] == nil, result["promoted_metadata"] == nil,
                      let post = parseGraphQLTweetResult(result, dateFormatter: formatter),
                      post.feedVideo != nil, seen.insert(post.id).inserted else { continue }
                posts.append(post)
            }
        }
        return posts
    }
}
