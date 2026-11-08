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
    // Starts silent, as videos that play by themselves should; the rail's speaker button turns the sound on
    var isMuted = true
    private(set) var isLoading = false
    // Why the feed is empty, in the reader's language
    private(set) var emptyReason: String?

    // The post the feed was started from, asked about again for each later batch
    @ObservationIgnored private var seed: (id: String, screenName: String)?
    @ObservationIgnored private var keepsFeedOnNextEntry = false
    // The posts feeds have been started from, and the videos already watched, kept across launches: at launch For You
    // is the saved snapshot, so without them every launch would start from the same post and X would answer with
    // much the same videos.
    @ObservationIgnored private var usedSeeds = RecentIDs(key: "Tweetintosh_VideosUsedSeeds", limit: 200)
    @ObservationIgnored private var seen = RecentIDs(key: "Tweetintosh_VideosSeen", limit: 1000)
    // Bumped when the feed is started again, so a batch for the old one is thrown away
    @ObservationIgnored private var generation = 0
    // Batches in a row that added nothing new: X has run out, or keeps sending what was watched already, so the end of
    // the feed is the end
    @ObservationIgnored private var emptyBatches = 0
    private static let maxEmptyBatches = 4
    // Loads ahead once the reader is this close to the last video, so the next one is there when the swipe lands
    private static let loadAheadCount = 3
    // How many of the next videos are downloaded ahead, one at a time and nearest first, so the very next one is
    // ready soonest. A page's player only exists once the page is on screen (the stack builds the next one when a swipe
    // begins), so without this every arrival waited for the network.
    private static let downloadAheadCount = 3
    // Videos this far behind the one being watched give their downloads back; the nearer ones stay, for going back
    private static let keepBehindCount = 5

    // The download under way, and the videos this feed put in the disk cache itself. Only those are removed again:
    // a video the timeline cached is the timeline's.
    @ObservationIgnored private var download: (url: String, task: URLSessionDownloadTask)?
    @ObservationIgnored private var downloadedVideos = Set<String>()

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

    // Entering the tab starts a new feed each time, as opening X's video viewer does, from a video in For You that
    // hasn't started one yet; a feed kept from last time would open on the same video again. The one exception is a
    // feed just started from a post the reader chose ("Open in Videos").
    func prepare() {
        if keepsFeedOnNextEntry {
            keepsFeedOnNextEntry = false
            return
        }
        let home = TimelineViewModel.shared
        let candidates = (home.forYouTweets.isEmpty ? home.tweets : home.forYouTweets).filter { $0.feedVideo != nil }
        // Any video post not started from or watched yet, picked at random so two launches on the same snapshot differ
        let unused = candidates.filter { !usedSeeds.contains($0.canonicalId) && !seen.contains($0.canonicalId) }
        guard let seedPost = unused.randomElement() ?? candidates.randomElement() else {
            generation += 1
            posts = []
            currentID = nil
            isLoading = false
            emptyReason = LocalizationManager.shared.t("videos_no_seed")
            return
        }
        start(from: seedPost)
    }

    // A new feed starting with this post, which shows at once while the rest loads. Kept when the tab is entered
    // straight afterwards, which is how "Open in Videos" arrives.
    func start(from post: Tweet, keepingOnEntry: Bool = false) {
        keepsFeedOnNextEntry = keepingOnEntry
        usedSeeds.insert(post.canonicalId)
        // The last feed's downloads are of no use to this one
        cancelDownload()
        downloadedVideos.forEach { MediaCacheManager.shared.removeCachedVideo(for: $0) }
        downloadedVideos.removeAll()
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
        guard let seed = seed, !isLoading, emptyBatches < Self.maxEmptyBatches else { return }
        isLoading = true
        let generation = generation
        APIClient.shared.fetchImmersiveMedia(pinnedPostId: seed.id, authorScreenName: seed.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.generation == generation else { return }
                self.isLoading = false
                switch result {
                case .success(let batch):
                    // The starting post is already first; keep each video once, by its own post or the one it reposts,
                    // and leave out the ones watched before
                    let known = Set(self.posts.map(\.canonicalId))
                    let fresh = batch.filter { !known.contains($0.canonicalId) && !self.seen.contains($0.canonicalId) }
                    self.emptyBatches = fresh.isEmpty ? self.emptyBatches + 1 : 0
                    self.posts.append(contentsOf: fresh)
                    self.downloadAhead()
                    // A short batch, or one that was all repeats, would leave nothing to swipe to
                    if let index = self.currentIndex, index >= self.posts.count - Self.loadAheadCount {
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
        if let index = currentIndex { seen.insert(posts[index].canonicalId) }
        if let index = currentIndex, index >= posts.count - Self.loadAheadCount { loadMore() }
        releaseDownloadsBehind()
        downloadAhead()
        if !NavigationManager.shared.sidebarExpanded { NavigationManager.shared.hideVideosChrome() }
    }

    // MARK: Downloading ahead

    // The file a player looks for first in the disk cache (see MediaHelpers.previewPlaybackURL)
    private static func cacheURL(of post: Tweet) -> String? {
        post.feedVideo?.videoInfo?.highestBitrateVariant?.url
    }

    // Fetches the first of the next few videos that isn't on disk yet, then, when it lands, the one after. A download
    // that falls outside that window, because the reader has moved past it, is dropped for the one now nearest.
    private func downloadAhead() {
        guard let index = currentIndex else { return }
        let cache = MediaCacheManager.shared
        let window = Array(posts.dropFirst(index + 1).prefix(Self.downloadAheadCount))
        // The stills and avatars that show before the video does are small; they all go at once
        cache.prefetchImages(urls: window.flatMap { [$0.feedVideo?.mediaUrl, $0.author.avatarUrl].compactMap { $0 } })

        let wanted = window.compactMap(Self.cacheURL)
        if let current = download {
            if wanted.contains(current.url) { return }
            cancelDownload()
        }
        guard let next = wanted.first(where: { cache.cachedVideoURL(for: $0) == nil }),
              let url = URL(string: next) else { return }
        let generation = generation
        let task = Self.downloadSession.downloadTask(with: url) { [weak self] tempURL, response, error in
            let ok = error == nil && tempURL != nil
                && ((response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false)
                && cache.storeDownloadedVideo(at: tempURL!, for: next)
            DispatchQueue.main.async {
                guard let self = self, self.download?.url == next else { return }
                self.download = nil
                if ok {
                    // Kept track of even if the feed has moved on, so it is removed with the rest
                    self.downloadedVideos.insert(next)
                    if self.generation != generation { cache.removeCachedVideo(for: next) }
                }
                if self.generation == generation && ok { self.downloadAhead() }
            }
        }
        download = (next, task)
        task.priority = URLSessionTask.highPriority
        task.resume()
    }

    // Its own connections: the shared session's are often taken by the timeline's prefetching, behind which the next
    // video waited long enough to be passed before it arrived
    private static let downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private func cancelDownload() {
        download?.task.cancel()
        download = nil
    }

    // Once the reader is more than a few videos on, the earliest downloads are given back
    private func releaseDownloadsBehind() {
        guard let index = currentIndex, index > Self.keepBehindCount else { return }
        for post in posts.prefix(index - Self.keepBehindCount) {
            guard let url = Self.cacheURL(of: post), downloadedVideos.remove(url) != nil else { continue }
            MediaCacheManager.shared.removeCachedVideo(for: url)
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

// MARK: - Recent IDs

// A set of ids saved in the defaults, oldest dropped first past `limit`, so it stays small however long it is used
struct RecentIDs {
    private let key: String
    private let limit: Int
    private var order: [String]
    private var members: Set<String>

    init(key: String, limit: Int) {
        self.key = key
        self.limit = limit
        order = UserDefaults.standard.stringArray(forKey: key) ?? []
        members = Set(order)
    }

    func contains(_ id: String) -> Bool { members.contains(id) }

    mutating func insert(_ id: String) {
        guard !members.contains(id) else { return }
        order.append(id)
        members.insert(id)
        if order.count > limit {
            order.prefix(order.count - limit).forEach { members.remove($0) }
            order.removeFirst(order.count - limit)
        }
        UserDefaults.standard.set(order, forKey: key)
    }
}
