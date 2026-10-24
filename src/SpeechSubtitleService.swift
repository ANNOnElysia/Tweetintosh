//
//  SpeechSubtitleService.swift
//  MaX - Headless Data-driven Client
//

import Foundation
import Speech
import AVFoundation

struct SubtitleCue: Identifiable {
    var id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
}

enum SubtitleStatus: Equatable {
    case idle
    case downloading(progress: Double)
    case transcribing
    case active(cueCount: Int)
    case failed(message: String)
}

final class SpeechSubtitleService: ObservableObject {
    static let shared = SpeechSubtitleService()
    
    @Published var status: SubtitleStatus = .idle
    @Published var currentCueText: String = ""
    @Published var cues: [SubtitleCue] = []
    
    private var recognitionTask: SFSpeechRecognitionTask?
    private var downloadTask: URLSessionDownloadTask?
    private var tempAudioFile: URL?
    private var activeMediaId: String?
    
    // Auto-detect or select locale
    var preferredLocale: Locale {
        // Can be configured or defaults to system locale
        return Locale.current
    }
    
    func reset() {
        cancel()
        status = .idle
        currentCueText = ""
        cues = []
        activeMediaId = nil
    }
    
    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        
        if let temp = tempAudioFile {
            try? FileManager.default.removeItem(at: temp)
            tempAudioFile = nil
        }
    }
    
    /// Trigger speech recognition only on user explicit action
    func startRecognition(for media: TweetMedia) {
        guard let videoInfo = media.videoInfo else {
            status = .failed(message: "无可用视频音轨")
            return
        }
        
        // Pick best MP4 URL for audio extraction
        guard let targetUrlStr = videoInfo.highestBitrateVariant?.url ?? videoInfo.variants.first(where: { $0.url.hasSuffix(".mp4") })?.url,
              let targetUrl = URL(string: targetUrlStr) else {
            status = .failed(message: "无法获取可识别的音频源")
            return
        }
        
        reset()
        activeMediaId = media.id
        status = .downloading(progress: 0.0)
        
        // Request authorization if needed
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch authStatus {
                case .authorized:
                    self.downloadAndTranscribe(from: targetUrl, mediaId: media.id)
                case .denied:
                    self.status = .failed(message: "未授权麦克风与语音识别权限")
                case .restricted:
                    self.status = .failed(message: "语音识别在此设备上受限")
                case .notDetermined:
                    self.status = .failed(message: "等待语音识别授权")
                @unknown default:
                    self.status = .failed(message: "语音识别服务暂不可用")
                }
            }
        }
    }
    
    private func downloadAndTranscribe(from url: URL, mediaId: String) {
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("max_sub_\(mediaId).mp4")
        self.tempAudioFile = tempUrl
        
        // If already cached locally, skip download
        if FileManager.default.fileExists(atPath: tempUrl.path) {
            self.transcribeLocalFile(at: tempUrl, mediaId: mediaId)
            return
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        
        downloadTask = session.downloadTask(with: url) { [weak self] location, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    if (error as NSError).code != NSURLErrorCancelled {
                        self.status = .failed(message: "下载视频音轨失败")
                    }
                }
                return
            }
            
            guard let location = location else {
                DispatchQueue.main.async {
                    self.status = .failed(message: "音轨资源无效")
                }
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: tempUrl.path) {
                    try FileManager.default.removeItem(at: tempUrl)
                }
                try FileManager.default.moveItem(at: location, to: tempUrl)
                
                DispatchQueue.main.async {
                    self.transcribeLocalFile(at: tempUrl, mediaId: mediaId)
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failed(message: "准备音频缓存失败")
                }
            }
        }
        
        downloadTask?.resume()
    }
    
    private func transcribeLocalFile(at fileUrl: URL, mediaId: String) {
        guard activeMediaId == mediaId else { return }
        
        // Choose recognizer for current or English/Japanese/Chinese locale
        let recognizer = SFSpeechRecognizer(locale: preferredLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            status = .failed(message: "当前语言暂不支持本地语音识别")
            return
        }
        
        let request = SFSpeechURLRecognitionRequest(url: fileUrl)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = true
        
        status = .transcribing
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.activeMediaId == mediaId else { return }
            
            if let result = result {
                var newCues: [SubtitleCue] = []
                for seg in result.bestTranscription.segments {
                    let start = seg.timestamp
                    let end = seg.timestamp + max(1.2, seg.duration)
                    let text = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        newCues.append(SubtitleCue(text: text, startTime: start, endTime: end))
                    }
                }
                
                DispatchQueue.main.async {
                    self.cues = newCues
                    self.status = .active(cueCount: newCues.count)
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    if (error as NSError).code != 203 && (error as NSError).code != NSURLErrorCancelled {
                        if self.cues.isEmpty {
                            self.status = .failed(message: "本地语音识别未获取到文本")
                        }
                    }
                }
            }
        }
    }
    
    /// Update visible subtitle cue based on player's current playback timestamp
    func updateCurrentTime(_ currentTime: TimeInterval) {
        guard !cues.isEmpty else {
            currentCueText = ""
            return
        }
        
        // Find exact active cue or cue active in window [startTime - 0.2, endTime + 0.4]
        if let match = cues.first(where: { currentTime >= ($0.startTime - 0.2) && currentTime <= ($0.endTime + 0.4) }) {
            if currentCueText != match.text {
                currentCueText = match.text
            }
        } else {
            if !currentCueText.isEmpty {
                currentCueText = ""
            }
        }
    }
}
