//
//  ArticleAPI.swift
//  Tweetintosh
//
//  Requests the full text of an X Article through the TweetDetail operation.
//

import Foundation

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
