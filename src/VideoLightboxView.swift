//
//  VideoLightboxView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit
import AVKit
import AVFoundation

// MARK: - Video Quality Options
enum VideoQualityOption: String, CaseIterable, Identifiable {
    case highest = "最高画质 (默认)"
    case auto = "自动 (自适应网络)"
    case p720 = "720p 高清"
    case p480 = "480p 标清"
    case p360 = "360p 流畅"
    
    var id: String { rawValue }
    
    var shortLabel: String {
        switch self {
        case .highest: return "最高"
        case .auto: return "自动"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
}

// MARK: - Video Lightbox Manager
final class VideoLightboxManager: ObservableObject {
    static let shared = VideoLightboxManager()
    
    @Published var isPresented: Bool = false
    @Published var currentTweet: Tweet?
    @Published var currentMedia: TweetMedia?
    
    @Published var selectedQuality: VideoQualityOption = .highest
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var isMuted: Bool = false
    
    @Published var isLiked: Bool = false
    @Published var isRetweeted: Bool = false
    @Published var favoriteCount: Int = 0
    @Published var retweetCount: Int = 0
    
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""
    
    @Published var isSubtitlesActive: Bool = false
    @Published var isControlsHovered: Bool = true
    
    var player: AVPlayer = AVPlayer()
    private var timeObserverToken: Any?
    private var keyMonitor: Any?
    private var controlsTimer: Timer?
    
    init() {
        setupTimeObserver()
    }
    
    func resetHoverTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isControlsHovered = false
                }
            }
        }
    }
    
    func present(tweet: Tweet, media: TweetMedia) {
        self.currentTweet = tweet
        self.currentMedia = media
        self.selectedQuality = .highest
        self.currentTime = 0
        self.duration = media.videoInfo?.durationSeconds ?? 0
        self.isLiked = false
        self.isRetweeted = false
        self.favoriteCount = tweet.favoriteCount
        self.retweetCount = tweet.retweetCount
        self.isSubtitlesActive = false
        
        SpeechSubtitleService.shared.reset()
        
        loadQualityStream(selectedQuality)
        setupKeyMonitor()
        
        withAnimation(.easeInOut(duration: 0.22)) {
            self.isPresented = true
        }
        
        player.play()
        self.isPlaying = true
    }
    
    func dismiss() {
        removeKeyMonitor()
        player.pause()
        self.isPlaying = false
        SpeechSubtitleService.shared.reset()
        
        withAnimation(.easeInOut(duration: 0.20)) {
            self.isPresented = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.currentTweet = nil
            self.currentMedia = nil
            self.player.replaceCurrentItem(with: nil)
        }
    }
    
    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.2 && duration > 0 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }
    
    func seek(to seconds: Double) {
        let clamped = max(0, min(duration, seconds))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = clamped
    }
    
    func seekRelative(by seconds: Double) {
        seek(to: currentTime + seconds)
    }
    
    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }
    
    func toggleSubtitles() {
        guard let media = currentMedia else { return }
        isSubtitlesActive.toggle()
        if isSubtitlesActive {
            SpeechSubtitleService.shared.startRecognition(for: media)
        } else {
            SpeechSubtitleService.shared.reset()
        }
    }
    
    func switchQuality(to quality: VideoQualityOption) {
        self.selectedQuality = quality
        let seekTime = self.currentTime
        let wasPlaying = self.isPlaying
        
        loadQualityStream(quality)
        
        seek(to: seekTime)
        if wasPlaying {
            player.play()
            self.isPlaying = true
        }
        
        showToastMessage("画质已切换为: \(quality.shortLabel)")
    }
    
    private func loadQualityStream(_ quality: VideoQualityOption) {
        guard let media = currentMedia, let videoInfo = media.videoInfo else { return }
        
        let targetUrlStr: String?
        switch quality {
        case .highest:
            targetUrlStr = videoInfo.highestBitrateVariant?.url ?? videoInfo.variants.first?.url
        case .auto:
            targetUrlStr = videoInfo.hlsVariant?.url ?? videoInfo.highestBitrateVariant?.url
        case .p720:
            targetUrlStr = matchVariant(in: videoInfo.sortedMp4Variants, targetBitrate: 832000)
        case .p480:
            targetUrlStr = matchVariant(in: videoInfo.sortedMp4Variants, targetBitrate: 400000)
        case .p360:
            targetUrlStr = matchVariant(in: videoInfo.sortedMp4Variants, targetBitrate: 256000)
        }
        
        guard let urlStr = targetUrlStr, let url = URL(string: urlStr) else { return }
        
        let item = AVPlayerItem(url: url)
        if quality == .auto {
            // Adaptive auto bitrate controlled by system HLS
            item.preferredPeakBitRate = 0
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
    }
    
    private func matchVariant(in mp4s: [TweetVideoVariant], targetBitrate: Int) -> String? {
        guard !mp4s.isEmpty else { return nil }
        var closest = mp4s[0]
        var minDiff = abs((closest.bitrate ?? 0) - targetBitrate)
        for v in mp4s {
            let diff = abs((v.bitrate ?? 0) - targetBitrate)
            if diff < minDiff {
                minDiff = diff
                closest = v
            }
        }
        return closest.url
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isPresented else { return }
            let secs = time.seconds
            if !secs.isNaN && !secs.isInfinite {
                self.currentTime = secs
                SpeechSubtitleService.shared.updateCurrentTime(secs)
            }
            if let currentItem = self.player.currentItem {
                let d = currentItem.duration.seconds
                if !d.isNaN && !d.isInfinite && d > 0 {
                    self.duration = d
                }
            }
        }
    }
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isPresented else { return event }
            switch event.keyCode {
            case 49: // Spacebar -> Toggle Play/Pause
                self.togglePlay()
                return nil
            case 123: // Left Arrow -> Seek -5s
                self.seekRelative(by: -5)
                return nil
            case 124: // Right Arrow -> Seek +5s
                self.seekRelative(by: 5)
                return nil
            case 46: // M key -> Toggle Mute
                self.toggleMute()
                return nil
            case 53: // Esc -> Dismiss
                self.dismiss()
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeKeyMonitor() {
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }
    }
    
    func downloadVideo() {
        guard let media = currentMedia,
              let videoInfo = media.videoInfo,
              let downloadUrl = videoInfo.highestBitrateVariant?.url ?? videoInfo.variants.first(where: { $0.url.hasSuffix(".mp4") })?.url,
              let url = URL(string: downloadUrl) else {
            showToastMessage("未找到可下载的完整视频源")
            return
        }
        
        showToastMessage("正在下载最高画质视频至 Downloads 目录...")
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileName = "Twitter_Video_\(media.id).mp4"
        let destination = downloadsDir.appendingPathComponent(fileName)
        
        URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            guard let self = self else { return }
            if let location = location {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: location, to: destination)
                    DispatchQueue.main.async {
                        self.showToastMessage("✅ 视频已保存至 Downloads: \(fileName)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showToastMessage("保存失败: \(error.localizedDescription)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showToastMessage("下载视频失败")
                }
            }
        }.resume()
    }
    
    func toggleLike() {
        isLiked.toggle()
        favoriteCount += isLiked ? 1 : -1
    }
    
    func toggleRetweet() {
        isRetweeted.toggle()
        retweetCount += isRetweeted ? 1 : -1
        showToastMessage(isRetweeted ? "已转推" : "已撤销转推")
    }
    
    func copyTweetLink() {
        guard let tweet = currentTweet else { return }
        let link = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        showToastMessage("推文链接已复制至剪贴板")
    }
    
    func showToastMessage(_ msg: String) {
        toastMessage = msg
        withAnimation(.easeInOut(duration: 0.20)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.20)) {
                self.showToast = false
            }
        }
    }
    
    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        removeKeyMonitor()
    }
}

// MARK: - Native AVPlayerView Wrapper
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none // Fully custom SwiftUI overlay controls
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - Video Lightbox Overlay View
struct VideoLightboxOverlay: View {
    @ObservedObject var manager = VideoLightboxManager.shared
    @ObservedObject var subtitleService = SpeechSubtitleService.shared
    
    var body: some View {
        if manager.isPresented {
            GeometryReader { windowGeo in
                let windowSize = windowGeo.size
                let boxWidth = windowSize.width * 0.75
                let boxHeight = windowSize.height * 0.75
                
                ZStack {
                    // 1. Dark Backdrop
                    Color.black
                        .opacity(0.94)
                        .ignoresSafeArea()
                        .onTapGesture {
                            manager.dismiss()
                        }
                    
                    // 2. Centered 3/4 Video Container
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            // Video Layer
                            NativePlayerView(player: manager.player)
                                .frame(width: boxWidth, height: boxHeight - 74)
                                .clipShape(RoundedCorner(tl: 12, tr: 12, bl: 0, br: 0))
                                .background(Color.black)
                                .onTapGesture {
                                    manager.togglePlay()
                                    manager.resetHoverTimer()
                                }
                            
                            // Center Play/Pause Floating Hint
                            if !manager.isPlaying {
                                Button(action: { manager.togglePlay() }) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .frame(width: 68, height: 68)
                                        .background(Circle().fill(Color.black.opacity(0.65)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                                        .shadow(radius: 12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Subtitles Display Banner
                            VStack {
                                Spacer()
                                
                                if manager.isSubtitlesActive {
                                    switch subtitleService.status {
                                    case .downloading(let p):
                                        subtitleStatusPill(icon: "arrow.down.circle", text: "正在下载音轨 (\(Int(p * 100))%)...")
                                    case .transcribing:
                                        subtitleStatusPill(icon: "waveform.badge.magnifyingglass", text: "正在使用本地神经引擎识别字幕...")
                                    case .failed(let err):
                                        subtitleStatusPill(icon: "exclamationmark.triangle", text: err)
                                    case .active:
                                        if !subtitleService.currentCueText.isEmpty {
                                            Text(subtitleService.currentCueText)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.80)))
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.20), lineWidth: 0.6))
                                                .padding(.horizontal, 24)
                                                .padding(.bottom, 16)
                                                .transition(.opacity)
                                        }
                                    default:
                                        EmptyView()
                                    }
                                }
                            }
                            
                            // Bottom Scrubber Bar Overlay
                            videoScrubberBar
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .opacity(manager.isControlsHovered || !manager.isPlaying ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.20), value: manager.isControlsHovered)
                        }
                        .frame(width: boxWidth, height: boxHeight - 74)
                        
                        // 3. Social & Download Action Bottom Dock
                        actionBottomBar
                            .frame(width: boxWidth, height: 74)
                            .background(Color(white: 0.12))
                            .clipShape(RoundedCorner(tl: 0, tr: 0, bl: 12, br: 12))
                    }
                    .frame(width: boxWidth, height: boxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.60), radius: 28, x: 0, y: 12)
                    .onHover { hovered in
                        manager.isControlsHovered = hovered
                        if hovered { manager.resetHoverTimer() }
                    }
                    
                    // 4. Top Header Bar (Close button + Quality Menu + CC button)
                    VStack {
                        HStack(alignment: .center, spacing: 12) {
                            // Video format pill
                            HStack(spacing: 6) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 11))
                                Text(manager.selectedQuality.shortLabel)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white.opacity(0.90))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                            .padding(.leading, max(24, (windowSize.width - boxWidth) / 2))
                            
                            Spacer()
                            
                            // CC (Speech-to-Text Subtitles) Button
                            Button(action: { manager.toggleSubtitles() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: manager.isSubtitlesActive ? "captions.bubble.fill" : "captions.bubble")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("CC")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(manager.isSubtitlesActive ? Color.accentColor : Color.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(manager.isSubtitlesActive ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 0.8))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("主动开启本地端侧字幕识别")
                            
                            // Quality Switcher Dropdown Menu
                            Menu {
                                ForEach(VideoQualityOption.allCases) { opt in
                                    Button(action: { manager.switchQuality(to: opt) }) {
                                        HStack {
                                            Text(opt.rawValue)
                                            if manager.selectedQuality == opt {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 12))
                                    Text(manager.selectedQuality.shortLabel)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9))
                                }
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                            }
                            .menuStyle(BorderlessButtonMenuStyle())
                            
                            // Close Button
                            Button(action: { manager.dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(white: 0.82))
                                    .padding(.trailing, max(20, (windowSize.width - boxWidth) / 2))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 18)
                        
                        Spacer()
                    }
                    
                    // 5. Toast Notification Banner
                    if manager.showToast {
                        VStack {
                            Text(manager.toastMessage)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color(white: 0.16)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                                .shadow(radius: 16)
                                .padding(.top, 70)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            
                            Spacer()
                        }
                    }
                }
            }
            .transition(.opacity)
            .zIndex(1000)
        }
    }
    
    // MARK: - Video Scrubber Bar
    private var videoScrubberBar: some View {
        HStack(spacing: 12) {
            // Play / Pause mini toggle
            Button(action: { manager.togglePlay() }) {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Current Time
            Text(formatTime(manager.currentTime))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            
            // Interactive Progress Slider
            GeometryReader { sliderGeo in
                let w = sliderGeo.size.width
                let progress = manager.duration > 0 ? min(1.0, max(0.0, manager.currentTime / manager.duration)) : 0
                
                ZStack(alignment: .leading) {
                    // Track Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 5)
                    
                    // Played Progress
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: w * progress, height: 5)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(radius: 3)
                        .offset(x: max(0, min(w - 12, w * progress - 6)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let ratio = max(0.0, min(1.0, val.location.x / w))
                            manager.seek(to: ratio * manager.duration)
                        }
                )
            }
            .frame(height: 14)
            
            // Duration
            Text(formatTime(manager.duration))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.70))
            
            // Mute / Unmute
            Button(action: { manager.toggleMute() }) {
                Image(systemName: manager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }
    
    // MARK: - Action Bottom Bar (Like, Repost, Share, Download)
    private var actionBottomBar: some View {
        HStack(spacing: 28) {
            // Like
            actionButton(
                icon: manager.isLiked ? "heart.fill" : "heart",
                count: manager.favoriteCount,
                color: manager.isLiked ? Color.red : Color.white.opacity(0.85)
            ) {
                manager.toggleLike()
            }
            
            // Repost
            actionButton(
                icon: "arrow.2.squarepath",
                count: manager.retweetCount,
                color: manager.isRetweeted ? Color.green : Color.white.opacity(0.85)
            ) {
                manager.toggleRetweet()
            }
            
            // Share
            Button(action: { manager.copyTweetLink() }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                    Text("分享链接")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Download MP4
            Button(action: { manager.downloadVideo() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15))
                    Text("一键保存 MP4")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 22)
    }
    
    private func actionButton(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func subtitleStatusPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
        .padding(.bottom, 16)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
