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
    case highest
    case auto
    case p720
    case p480
    case p360
    
    var id: String { rawValue }
    
    var localizedTitle: String {
        let loc = LocalizationManager.shared
        switch self {
        case .highest: return loc.t("video_quality_highest")
        case .auto: return loc.t("video_quality_auto")
        case .p720: return loc.t("video_quality_720p")
        case .p480: return loc.t("video_quality_480p")
        case .p360: return loc.t("video_quality_360p")
        }
    }
    
    var shortLabel: String {
        switch self {
        case .highest: return "MAX"
        case .auto: return "AUTO"
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
    @Published var isControlsHovered: Bool = true
    
    var player: AVPlayer = AVPlayer()
    private var timeObserverToken: Any?
    private var keyMonitor: Any?
    private var controlsTimer: Timer?
    
    init() {
        setupTimeObserver()
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
        self.isControlsHovered = true
        
        loadQualityStream(selectedQuality)
        setupEventMonitors()
        resetHoverTimer()
        
        withAnimation(.easeInOut(duration: 0.22)) {
            self.isPresented = true
        }
        
        player.play()
        self.isPlaying = true
    }
    
    func dismiss() {
        removeEventMonitors()
        controlsTimer?.invalidate()
        player.pause()
        self.isPlaying = false
        
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
        
        let msg = LocalizationManager.shared.format("video_quality_switched", ["quality": quality.shortLabel])
        showToastMessage(msg)
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
            }
            if let currentItem = self.player.currentItem {
                let d = currentItem.duration.seconds
                if !d.isNaN && !d.isInfinite && d > 0 {
                    self.duration = d
                }
            }
        }
    }
    
    private func setupEventMonitors() {
        removeEventMonitors()
        
        // Keyboard shortcuts: Space (play/pause), M (mute), Esc (exit)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isPresented else { return event }
            switch event.keyCode {
            case 49: // Spacebar -> Toggle Play/Pause
                self.togglePlay()
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
    
    private func removeEventMonitors() {
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }
    }
    
    func resetHoverTimer() {
        isControlsHovered = true
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
    
    func downloadVideo() {
        let loc = LocalizationManager.shared
        guard let media = currentMedia,
              let videoInfo = media.videoInfo,
              let downloadUrl = videoInfo.highestBitrateVariant?.url ?? videoInfo.variants.first(where: { $0.url.hasSuffix(".mp4") })?.url,
              let url = URL(string: downloadUrl) else {
            showToastMessage(loc.t("video_download_failed"))
            return
        }
        
        showToastMessage(loc.t("video_downloading"))
        
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
                        self.showToastMessage("✅ \(loc.t("video_saved_success")): \(fileName)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showToastMessage("\(loc.t("video_download_failed")): \(error.localizedDescription)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showToastMessage(loc.t("video_download_failed"))
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
    }
    
    func copyTweetLink() {
        guard let tweet = currentTweet else { return }
        let link = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        showToastMessage(LocalizationManager.shared.t("video_link_copied"))
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
        removeEventMonitors()
    }
}

// MARK: - Native AVPlayerView Wrapper
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
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
    @ObservedObject var loc = LocalizationManager.shared
    
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
                                .frame(width: boxWidth, height: boxHeight - 68)
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
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                        .frame(width: 64, height: 64)
                                        .background(
                                            ZStack {
                                                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                                                Color.black.opacity(0.40)
                                            }
                                            .clipShape(Circle())
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 0.8
                                                )
                                        )
                                        .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Bottom Floating Glass Scrubber Bar
                            videoScrubberBar
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .opacity(manager.isControlsHovered || !manager.isPlaying ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.20), value: manager.isControlsHovered)
                        }
                        .frame(width: boxWidth, height: boxHeight - 68)
                        
                        // 3. Social & Download Glass Bottom Dock
                        actionBottomBar
                            .frame(width: boxWidth, height: 68)
                    }
                    .frame(width: boxWidth, height: boxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.60), radius: 28, x: 0, y: 12)
                    .onHover { hovered in
                        manager.isControlsHovered = hovered
                        if hovered { manager.resetHoverTimer() }
                    }
                    
                    // 4. Top Header Bar: Clean single glass quality menu + Close button
                    VStack {
                        HStack(alignment: .center, spacing: 12) {
                            Spacer()
                            
                            // Quality Switcher Glass Dropdown Menu
                            Menu {
                                ForEach(VideoQualityOption.allCases) { opt in
                                    Button(action: { manager.switchQuality(to: opt) }) {
                                        HStack {
                                            Text(opt.localizedTitle)
                                            if manager.selectedQuality == opt {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 11))
                                    Text(manager.selectedQuality.shortLabel)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                                        Color.black.opacity(0.40)
                                    }
                                    .clipShape(Capsule())
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.08), Color.white.opacity(0.18)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.75
                                        )
                                        .allowsHitTesting(false)
                                )
                                .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 2)
                            }
                            .menuStyle(BorderlessButtonMenuStyle())
                            .fixedSize()
                            
                            // Close Button
                            Button(action: { manager.dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(white: 0.85))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.trailing, max(20, (windowSize.width - boxWidth) / 2))
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
                                .background(
                                    ZStack {
                                        VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                                        Color.black.opacity(0.50)
                                    }
                                    .clipShape(Capsule())
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                )
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
    
    // MARK: - Glass Video Scrubber Bar (HUD Frosted Glass Capsule)
    private var videoScrubberBar: some View {
        HStack(spacing: 12) {
            // Play / Pause mini toggle
            Button(action: { manager.togglePlay() }) {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Current Time
            Text(formatTime(manager.currentTime))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
            
            // Interactive Glass Progress Slider
            GeometryReader { sliderGeo in
                let w = sliderGeo.size.width
                let progress = manager.duration > 0 ? min(1.0, max(0.0, manager.currentTime / manager.duration)) : 0
                
                ZStack(alignment: .leading) {
                    // Frosted Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 5)
                    
                    // Played Progress: Bright Frosted Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * progress, height: 5)
                    
                    // Glass Thumb Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                        .shadow(color: Color.black.opacity(0.40), radius: 4, x: 0, y: 1)
                        .offset(x: max(0, min(w - 13, w * progress - 6.5)))
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
                .foregroundColor(.white.opacity(0.65))
            
            // Mute / Unmute
            Button(action: { manager.toggleMute() }) {
                Image(systemName: manager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(manager.isMuted ? 0.65 : 1.0))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.48)
            }
            .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 14, x: 0, y: 5)
    }
    
    // MARK: - Action Bottom Bar (Like, Repost, Share, Glass Download)
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
                        .font(.system(size: 13.5))
                    Text(loc.t("video_share_link"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Download MP4 (Frosted Glass Capsule Button)
            Button(action: { manager.downloadVideo() }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.white)
                    Text(loc.t("video_save_mp4"))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                        Color.white.opacity(0.14)
                    }
                    .clipShape(Capsule())
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 22)
        .background(
            ZStack {
                VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                Color.black.opacity(0.52)
            }
        )
        .clipShape(RoundedCorner(tl: 0, tr: 0, bl: 12, br: 12))
        .overlay(
            VStack {
                Divider()
                    .background(Color.white.opacity(0.10))
                Spacer()
            }
        )
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
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
