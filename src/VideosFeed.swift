//
//  VideosFeed.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The Videos tab's data: X's immersive video feed (ImmersiveMedia, the swipeable viewer at /status/<id>/mediaViewer on
//  X's mobile site), and the state of the one page being watched.
//

import SwiftUI
import AppKit

// MARK: - Request

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

extension Tweet {
    // The video this post shows in the Videos tab: its first proper video (a GIF is too short to be one)
    var feedVideo: TweetMedia? {
        media.first { $0.type == "video" && $0.videoInfo != nil }
    }
}

// MARK: - Feed

@Observable
final class VideosFeed: TweetMutationTarget {
    static let shared = VideosFeed()

    private(set) var posts: [Tweet] = []
    // The page on screen, shared by the scroll view and the keyboard so a swipe and ↓ always agree
    var currentID: String?
    var isPlaying = true
    var isMuted = false
    private(set) var isLoading = false
    // Why the feed is empty, in the reader's language
    private(set) var emptyReason: String?

    // The post the feed was started from, asked about again for each later batch
    @ObservationIgnored private var seed: (id: String, screenName: String)?
    // Bumped when the feed is started again, so a batch for the old one is thrown away
    @ObservationIgnored private var generation = 0
    // Two batches in a row that added nothing: X has run out, so the end of the feed is the end
    @ObservationIgnored private var emptyBatches = 0
    // Loads ahead once the reader is this close to the last video, so the next one is there when the swipe lands
    private static let loadAheadCount = 3
    // How many of the next videos are downloaded ahead. A page's player only exists once the page is on screen (the
    // stack builds the next one when a swipe begins), so without this every arrival waited for the network.
    private static let downloadAheadCount = 2

    private init() {
        TweetMutationHub.shared.register(self)
    }

    var currentIndex: Int? {
        guard let id = currentID else { return nil }
        return posts.firstIndex { $0.id == id }
    }

    var current: Tweet? {
        currentIndex.map { posts[$0] }
    }

    static var pageAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.35)
    }

    // Entering the tab. Keeps the feed it had; the first time, starts from the first video in For You.
    func prepare() {
        guard posts.isEmpty, !isLoading else { return }
        let home = TimelineViewModel.shared
        let candidates = home.forYouTweets.isEmpty ? home.tweets : home.forYouTweets
        guard let seedPost = candidates.first(where: { $0.feedVideo != nil }) else {
            emptyReason = LocalizationManager.shared.t("videos_no_seed")
            return
        }
        start(from: seedPost)
    }

    // A new feed starting with this post, which shows at once while the rest loads
    func start(from post: Tweet) {
        generation += 1
        emptyBatches = 0
        seed = (post.canonicalId, post.author.screenName)
        emptyReason = nil
        isLoading = false
        posts = [post]
        currentID = post.id
        isPlaying = true
        loadMore()
        downloadAhead()
    }

    func loadMore() {
        guard let seed = seed, !isLoading, emptyBatches < 2 else { return }
        isLoading = true
        let generation = generation
        APIClient.shared.fetchImmersiveMedia(pinnedPostId: seed.id, authorScreenName: seed.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.generation == generation else { return }
                self.isLoading = false
                switch result {
                case .success(let batch):
                    // The starting post is already first; keep each video once, by its own post or the one it reposts
                    let known = Set(self.posts.map(\.canonicalId))
                    let fresh = batch.filter { !known.contains($0.canonicalId) }
                    self.emptyBatches = fresh.isEmpty ? self.emptyBatches + 1 : 0
                    self.posts.append(contentsOf: fresh)
                    self.downloadAhead()
                    // A short first batch would leave nothing to swipe to
                    if let index = self.currentIndex, index >= self.posts.count - Self.loadAheadCount, !fresh.isEmpty {
                        self.loadMore()
                    }
                case .failure:
                    if self.posts.count <= 1 { self.emptyReason = LocalizationManager.shared.t("videos_load_failed") }
                }
            }
        }
    }

    // MARK: Moving

    func move(by delta: Int) {
        guard let index = currentIndex, posts.indices.contains(index + delta) else {
            // The standard Mac answer to a command that can go no further
            NSSound.beep()
            return
        }
        withAnimation(Self.pageAnimation) { currentID = posts[index + delta].id }
    }

    // Whenever the page on screen changes, however it changed
    func didSettle() {
        // Arriving on a video means you want to watch it, as on X's own feed
        isPlaying = true
        if let index = currentIndex, index >= posts.count - Self.loadAheadCount { loadMore() }
        downloadAhead()
        if !NavigationManager.shared.sidebarExpanded { NavigationManager.shared.hideVideosChrome() }
    }

    // Into the disk cache that a player looks in first (the same file the timeline's prefetching fetches), with the
    // stills and avatars that show before the video does
    private func downloadAhead() {
        guard let index = currentIndex else { return }
        let cache = MediaCacheManager.shared
        for post in posts.dropFirst(index + 1).prefix(Self.downloadAheadCount) {
            guard let media = post.feedVideo else { continue }
            cache.prefetchImages(urls: [media.mediaUrl, post.author.avatarUrl].compactMap { $0 })
            if let url = media.videoInfo?.highestBitrateVariant?.url { cache.prefetchVideo(urlStr: url) }
        }
    }

    func togglePlayback() {
        guard current != nil else { NSSound.beep(); return }
        isPlaying.toggle()
    }

    // MARK: TweetMutationTarget

    func applyMutation(id: String, transform: (inout Tweet) -> Void) {
        for index in posts.indices where posts[index].canonicalId == id {
            transform(&posts[index])
        }
    }

    func copy(of id: String) -> Tweet? {
        posts.first { $0.canonicalId == id }
    }

    func removePost(id: String) {
        guard posts.contains(where: { $0.isCopy(ofPost: id) }) else { return }
        let wasCurrent = current?.isCopy(ofPost: id) == true
        let index = currentIndex ?? 0
        posts.removeAll { $0.isCopy(ofPost: id) }
        if wasCurrent { currentID = posts.indices.contains(index) ? posts[index].id : posts.last?.id }
    }
}
