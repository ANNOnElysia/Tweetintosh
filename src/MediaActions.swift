//
//  MediaActions.swift
//  Tweetintosh - macOS Native Twitter/X Client
//

import SwiftUI
import AppKit

// MARK: - App Toast Manager
final class AppToastManager: ObservableObject {
    static let shared = AppToastManager()
    
    @Published var message: String = ""
    @Published var icon: String? = nil
    private var dismissWorkItem: DispatchWorkItem?
    
    func show(_ text: String, icon: String? = nil, duration: Double = 2.4) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissWorkItem?.cancel()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                self.message = text
                self.icon = icon
            }
            
            let item = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.message = ""
                    self?.icon = nil
                }
            }
            self.dismissWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        }
    }
}

// MARK: - Media Helpers
enum MediaHelpers {
    /// Converts any Twitter photo URL into its original, full-resolution uncompressed asset URL
    static func originalImageUrl(_ urlString: String) -> String {
        guard urlString.contains("pbs.twimg.com/media") else { return urlString }
        
        let components = urlString.components(separatedBy: "?")
        let base = components[0]
        
        var format = "jpg"
        if components.count > 1 {
            let query = components[1]
            let queryItems = query.components(separatedBy: "&")
            for item in queryItems {
                let pair = item.components(separatedBy: "=")
                if pair.count == 2, pair[0] == "format" {
                    format = pair[1]
                }
            }
        } else {
            if base.lowercased().hasSuffix(".png") {
                format = "png"
            }
        }
        
        let cleanBase = base.replacingOccurrences(of: #"\.(jpg|jpeg|png|webp)$"#, with: "", options: .regularExpression)
        return "\(cleanBase)?format=\(format)&name=orig"
    }
    
    /// For playing a video small: a prefetched file when there is one, otherwise a mid-bitrate stream that starts quickly
    static func previewPlaybackURL(for media: TweetMedia) -> URL? {
        guard let info = media.videoInfo else { return nil }
        if let best = info.highestBitrateVariant?.url, let cached = MediaCacheManager.shared.cachedVideoURL(for: best) {
            return cached
        }
        let variants = info.sortedMp4Variants
        let pick = variants.first(where: { ($0.bitrate ?? 0) <= 2_200_000 }) ?? variants.last
        return pick.flatMap { URL(string: $0.url) }
    }

    /// Finds the highest bitrate / highest resolution MP4 variant available for a video
    static func bestVideoUrl(_ media: TweetMedia) -> String {
        if let variants = media.videoInfo?.variants {
            let mp4s = variants
                .filter { $0.contentType == "video/mp4" }
                .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
            if let best = mp4s.first {
                return best.url
            }
        }
        return media.mediaUrl
    }
}

// MARK: - Media Action Dispatcher
final class MediaActions {
    static let shared = MediaActions()
    
    // 1. 复制 (Copy Media at Original Resolution)
    func copyMedia(media: TweetMedia, tweet: Tweet?) {
        let loc = LocalizationManager.shared
        if media.isVideo {
            let videoUrl = MediaHelpers.bestVideoUrl(media)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(videoUrl, forType: .string)
            if let url = URL(string: videoUrl) {
                pb.writeObjects([url as NSURL])
            }
            AppToastManager.shared.show(loc.t("media_link_copied"), icon: "doc.on.doc")
        } else {
            let origUrl = MediaHelpers.originalImageUrl(media.mediaUrl)
            if let cached = ImageCache.shared.image(for: origUrl) {
                writeImageToPasteboard(cached, origUrl: origUrl)
                AppToastManager.shared.show(loc.t("image_copied"), icon: "checkmark.circle.fill")
                return
            }
            
            AppToastManager.shared.show(loc.t("fetching_original_image"), icon: "arrow.down.circle")
            guard let url = URL(string: origUrl) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let self = self, let data = data, let img = NSImage(data: data) else {
                    DispatchQueue.main.async {
                        AppToastManager.shared.show("Failed to copy image", icon: "xmark.circle")
                    }
                    return
                }
                ImageCache.shared.setImage(img, for: origUrl)
                DispatchQueue.main.async {
                    self.writeImageToPasteboard(img, origUrl: origUrl)
                    AppToastManager.shared.show(loc.t("image_copied"), icon: "checkmark.circle.fill")
                }
            }.resume()
        }
    }
    
    private func writeImageToPasteboard(_ image: NSImage, origUrl: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
            if let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            }
        }
        pb.writeObjects([image])
        pb.setString(origUrl, forType: .string)
    }
    
    // 2. 保存图片 / 保存视频 (Save As at Original Resolution)
    func saveMedia(media: TweetMedia, tweet: Tweet?) {
        if media.isVideo {
            saveVideo(media: media, tweet: tweet)
        } else {
            saveImage(media: media, tweet: tweet)
        }
    }
    
    private func saveImage(media: TweetMedia, tweet: Tweet?) {
        let loc = LocalizationManager.shared
        let origUrl = MediaHelpers.originalImageUrl(media.mediaUrl)
        let isPng = origUrl.contains("format=png")
        let ext = isPng ? "png" : "jpg"
        let author = tweet?.author.screenName ?? "tweet"
        let defaultName = "\(author)_\(media.id).\(ext)"
        
        let panel = NSSavePanel()
        panel.title = loc.t("save_image_as")
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = isPng ? [.png] : [.jpeg]
        }
        
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let onChosen: (URL) -> Void = { destination in
            guard let url = URL(string: origUrl) else { return }
            AppToastManager.shared.show(loc.t("downloading_media"), icon: "arrow.down.circle")
            
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard let data = data, error == nil else {
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(loc.t("video_download_failed"), icon: "xmark.circle")
                    }
                    return
                }
                do {
                    try data.write(to: destination)
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(loc.t("image_saved"), icon: "checkmark.circle.fill")
                    }
                } catch {
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(error.localizedDescription, icon: "xmark.circle")
                    }
                }
            }.resume()
        }
        
        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let dest = panel.url {
                    onChosen(dest)
                }
            }
        } else {
            if panel.runModal() == .OK, let dest = panel.url {
                onChosen(dest)
            }
        }
    }
    
    private func saveVideo(media: TweetMedia, tweet: Tweet?) {
        let loc = LocalizationManager.shared
        let videoUrl = MediaHelpers.bestVideoUrl(media)
        let author = tweet?.author.screenName ?? "tweet"
        let defaultName = "\(author)_\(media.id).mp4"
        
        let panel = NSSavePanel()
        panel.title = loc.t("save_video_as")
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.mpeg4Movie, .movie]
        }
        
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let onChosen: (URL) -> Void = { destination in
            guard let url = URL(string: videoUrl) else { return }
            AppToastManager.shared.show(loc.t("video_downloading"), icon: "arrow.down.circle")
            
            URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                guard let tempURL = tempURL, error == nil else {
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(loc.t("video_download_failed"), icon: "xmark.circle")
                    }
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(loc.t("video_saved"), icon: "checkmark.circle.fill")
                    }
                } catch {
                    DispatchQueue.main.async {
                        AppToastManager.shared.show(error.localizedDescription, icon: "xmark.circle")
                    }
                }
            }.resume()
        }
        
        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let dest = panel.url {
                    onChosen(dest)
                }
            }
        } else {
            if panel.runModal() == .OK, let dest = panel.url {
                onChosen(dest)
            }
        }
    }
    
    // 3. 保存 URL (Copy Media Link at Original Quality)
    func copyMediaUrl(media: TweetMedia) {
        let loc = LocalizationManager.shared
        let urlStr = media.isVideo ? MediaHelpers.bestVideoUrl(media) : MediaHelpers.originalImageUrl(media.mediaUrl)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urlStr, forType: .string)
        if let url = URL(string: urlStr) {
            pb.writeObjects([url as NSURL])
        }
        AppToastManager.shared.show(loc.t("media_link_copied"), icon: "link")
    }
    
    // 4. 转帖 (Quote / Retweet)
    func toggleRetweet(tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let loc = LocalizationManager.shared
        TimelineViewModel.shared.toggleRetweet(for: tweet)
        let msg = tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet")
        AppToastManager.shared.show(msg, icon: "arrow.2.squarepath")
    }
    
    func quoteTweet(tweet: Tweet) {
        NavigationManager.shared.openComposer(quoting: tweet)
    }
    
    // 5. 分享 (Share...)
    func shareMedia(media: TweetMedia, tweet: Tweet?, from view: NSView? = nil) {
        var items: [Any] = []
        if media.isVideo {
            let vUrl = MediaHelpers.bestVideoUrl(media)
            if let u = URL(string: vUrl) { items.append(u) }
        } else {
            let origUrl = MediaHelpers.originalImageUrl(media.mediaUrl)
            if let cached = ImageCache.shared.image(for: origUrl) {
                items.append(cached)
            } else if let u = URL(string: origUrl) {
                items.append(u)
            }
        }
        if let tweet = tweet, let tweetUrl = URL(string: "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)") {
            items.append(tweetUrl)
        }
        guard !items.isEmpty else { return }
        
        let picker = NSSharingServicePicker(items: items)
        if let targetView = view ?? NSApp.keyWindow?.contentView {
            picker.show(relativeTo: targetView.bounds, of: targetView, preferredEdge: .minY)
        }
    }
}

// MARK: - Reusable Context Menu Modifier for Media
struct MediaContextMenuModifier: ViewModifier {
    let media: TweetMedia
    let tweet: Tweet?
    @ObservedObject var loc = LocalizationManager.shared
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                // 1. 复制 (Copy Image / Video)
                Button {
                    MediaActions.shared.copyMedia(media: media, tweet: tweet)
                } label: {
                    Label(
                        media.isVideo ? loc.t("copy_video_link") : loc.t("copy_original_image"),
                        systemImage: "doc.on.doc"
                    )
                }
                
                // 2. 保存图片 / 保存视频 (Save Image / Save Video)
                Button {
                    MediaActions.shared.saveMedia(media: media, tweet: tweet)
                } label: {
                    Label(
                        media.isVideo ? loc.t("save_video_as") : loc.t("save_image_as"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                
                // 3. 保存 URL (Copy Media Link)
                Button {
                    MediaActions.shared.copyMediaUrl(media: media)
                } label: {
                    Label(
                        loc.t("copy_media_link"),
                        systemImage: "link"
                    )
                }
                
                Divider()
                
                // 4. 转帖 (Quote / Retweet)
                if let tweet = tweet {
                    Menu {
                        Button {
                            MediaActions.shared.toggleRetweet(tweet: tweet)
                        } label: {
                            Label(tweet.isRetweeted ? loc.t("undo_retweet") : loc.t("retweet"), systemImage: "arrow.2.squarepath")
                        }
                        
                        Button {
                            MediaActions.shared.quoteTweet(tweet: tweet)
                        } label: {
                            Label(loc.t("quote_tweet"), systemImage: "quote.bubble")
                        }
                    } label: {
                        Label(loc.t("repost"), systemImage: "arrow.2.squarepath")
                    }
                }
                
                // 5. 分享 (Share...)
                Button {
                    MediaActions.shared.shareMedia(media: media, tweet: tweet)
                } label: {
                    Label(loc.t("share"), systemImage: "square.and.arrow.up")
                }
            }
    }
}

extension View {
    func mediaContextMenu(media: TweetMedia, tweet: Tweet?) -> some View {
        self.modifier(MediaContextMenuModifier(media: media, tweet: tweet))
    }
}
