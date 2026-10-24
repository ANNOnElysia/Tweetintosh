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
    @Published var isScrubbing: Bool = false
    
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
        let interval = CMTime(seconds: 0.04, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isPresented, !self.isScrubbing else { return }
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

// MARK: - Video Lightbox Overlay View (Full Window Immersive Stage)
struct VideoLightboxOverlay: View {
    @ObservedObject var manager = VideoLightboxManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        if manager.isPresented {
            GeometryReader { windowGeo in
                let windowSize = windowGeo.size
                
                ZStack {
                    // 1. Full-Window Pure Obsidian Backdrop
                    Color.black
                        .ignoresSafeArea()
                        .onTapGesture {
                            manager.dismiss()
                        }
                    
                    // 2. Full-Window Immersive Video Player Layer
                    NativePlayerView(player: manager.player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.togglePlay()
                            manager.resetHoverTimer()
                        }
                    
                    // 3. Center Screen Play/Pause Indicator (Dead Center, No Overlap)
                    if !manager.isPlaying {
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                manager.togglePlay()
                            }
                            manager.resetHoverTimer()
                        }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .offset(x: 2) // optical center alignment for play triangle
                                .frame(width: 72, height: 72)
                                .background(
                                    videoGlassBackground(shape: Circle(), accentTint: 0.22)
                                )
                                .overlay(
                                    videoGlassBorder(shape: Circle(), isAccent: true)
                                )
                                .shadow(color: Color.black.opacity(0.50), radius: 20, x: 0, y: 6)
                                .shadow(color: ThemeManager.accent.opacity(0.35), radius: 12, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    
                    // 4. Top Header Bar: Clean Glass Quality Menu + Close Button
                    VStack {
                        HStack(alignment: .center, spacing: 14) {
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6.5)
                                .background(
                                    videoGlassBackground(shape: Capsule(), accentTint: 0.10)
                                )
                                .overlay(
                                    videoGlassBorder(shape: Capsule(), isAccent: false)
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
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        
                        Spacer()
                    }
                    .opacity(manager.isControlsHovered || !manager.isPlaying ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.22), value: manager.isControlsHovered)
                    
                    // 5. Bottom Floating Unified Glass Control Dock
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            // Smooth Scrubber Bar
                            videoScrubberBar
                            
                            // Social Actions & Themed Glass Download Button (NO white divider)
                            actionBottomBar
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: min(windowSize.width - 56, 760))
                        .background(
                            videoGlassBackground(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), accentTint: 0.06)
                        )
                        .overlay(
                            videoGlassBorder(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), isAccent: false)
                        )
                        .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 10)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                    }
                    .opacity(manager.isControlsHovered || !manager.isPlaying ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.22), value: manager.isControlsHovered)
                    
                    // 6. Toast Notification Banner
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
                .onHover { hovered in
                    manager.isControlsHovered = hovered
                    if hovered { manager.resetHoverTimer() }
                }
            }
            .transition(.opacity)
            .zIndex(1000)
        }
    }
    
    // MARK: - Dual Glass Helper (Liquid Glass Mode vs Frosted Blur Glass Mode)
    @ViewBuilder
    private func videoGlassBackground<S: Shape>(shape: S, accentTint: Double = 0.0) -> some View {
        if #available(macOS 26.0, *), theme.useLiquidGlass {
            let glass: Glass = accentTint > 0
                ? .regular.tint(ThemeManager.accent.opacity(accentTint)).interactive()
                : .regular.interactive()
            shape
                .fill(
                    accentTint > 0
                        ? ThemeManager.accent.opacity(accentTint * 0.70)
                        : Color.black.opacity(0.35)
                )
                .glassEffect(glass, in: shape)
        } else {
            // High-grade Gaussian Frosted Blur (Active when Liquid Glass is off)
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.48)
                if accentTint > 0 {
                    ThemeManager.accent.opacity(accentTint)
                }
            }
            .clipShape(shape)
        }
    }
    
    @ViewBuilder
    private func videoGlassBorder<S: Shape>(shape: S, isAccent: Bool = false) -> some View {
        shape
            .stroke(
                LinearGradient(
                    colors: isAccent ? [
                        ThemeManager.accent.opacity(0.85),
                        Color.white.opacity(0.45),
                        ThemeManager.accent.opacity(0.40)
                    ] : [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
    }
    
    // MARK: - Smooth Glass Video Scrubber Bar (Theme-tinted, 25fps Interpolated)
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
            
            // Interactive Smooth Glass Progress Slider
            GeometryReader { sliderGeo in
                let w = sliderGeo.size.width
                let progress = manager.duration > 0 ? min(1.0, max(0.0, manager.currentTime / manager.duration)) : 0
                
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 5)
                    
                    // Played Progress: Theme-accent Gradient Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ThemeManager.accent.opacity(0.85), ThemeManager.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, w * CGFloat(progress)), height: 5)
                        .animation(manager.isScrubbing ? nil : .linear(duration: 0.04), value: progress)
                    
                    // Theme-accent Glow Thumb Knob
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                        Circle()
                            .stroke(ThemeManager.accent, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                    }
                    .shadow(color: ThemeManager.accent.opacity(0.60), radius: 6, x: 0, y: 1)
                    .offset(x: max(0, min(w - 14, w * CGFloat(progress) - 7)))
                    .animation(manager.isScrubbing ? nil : .linear(duration: 0.04), value: progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            manager.isScrubbing = true
                            let ratio = max(0.0, min(1.0, val.location.x / w))
                            manager.currentTime = ratio * manager.duration
                            manager.resetHoverTimer()
                        }
                        .onEnded { val in
                            let ratio = max(0.0, min(1.0, val.location.x / w))
                            manager.seek(to: ratio * manager.duration)
                            manager.isScrubbing = false
                            manager.resetHoverTimer()
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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Action Bottom Bar (Like, Repost, Share, Themed Glass Download)
    private var actionBottomBar: some View {
        HStack(spacing: 26) {
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
            
            // Share Link
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
            
            // Download MP4 (Themed Glass Capsule Button)
            Button(action: { manager.downloadVideo() }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(loc.t("video_save_mp4"))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    videoGlassBackground(shape: Capsule(), accentTint: 0.32)
                )
                .overlay(
                    videoGlassBorder(shape: Capsule(), isAccent: true)
                )
                .shadow(color: ThemeManager.accent.opacity(0.40), radius: 10, x: 0, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
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
