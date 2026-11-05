//
//  ReplyComposerSheet.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

final class ReplyComposerState: ObservableObject {
    @Published var replyText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String? = nil
    @Published var attachments: [ComposerAttachment] = []
    @Published var uploadStatus: String? = nil
}

struct ReplyComposerSheet: View {
    let tweet: Tweet
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @StateObject private var state = ReplyComposerState()
    
    private let characterLimit = 280
    
    private var remainingCharacters: Int {
        characterLimit - state.replyText.count
    }
    
    private var canSend: Bool {
        let trimmed = state.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !state.attachments.isEmpty) && remainingCharacters >= 0 && !state.isSending
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .onAppear { WebKitWriteChannel.shared.warmUp() }

            
            Divider()
                .background(ThemeManager.divider)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    originalTweetSnippet
                    composerInputRow
                    
                    if !state.attachments.isEmpty {
                        ComposerAttachmentStrip(attachments: $state.attachments, isDisabled: state.isSending)
                            .padding(.top, 8)
                    }
                    
                    if let status = state.uploadStatus {
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    
                    if let error = state.errorMessage {
                        errorBanner(error)
                    }
                }
            }
            
            Divider()
                .background(ThemeManager.divider)
            
            bottomControlsBar
        }
        .frame(width: 520, height: 340 + (state.attachments.isEmpty ? 0 : 110))
        .background(ThemeManager.background)
        .onAppear { NavigationManager.shared.isReplyComposerOpen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_CancelReply"))) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_AttachMedia"))) { _ in
            chooseMedia()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_PasteMedia"))) { _ in
            addMedia(MediaAttachments.pastedMedia(from: .general), pasted: true)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async { addMedia([url], pasted: false) }
                }
            }
            return true
        }
        .onDisappear {
            NavigationManager.shared.isReplyComposerOpen = false
            state.attachments.filter(\.isTemporaryCopy).forEach { try? FileManager.default.removeItem(at: $0.url) }
        }
    }
    
    private func chooseMedia() {
        guard !state.isSending else { return }
        MediaAttachments.pick(parent: nil) { urls in
            addMedia(urls, pasted: false)
        }
    }
    
    private func addMedia(_ urls: [URL], pasted: Bool) {
        guard !state.isSending else { return }
        state.errorMessage = MediaAttachments.add(urls, to: &state.attachments, pasted: pasted)
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text(loc.t("cancel"))
                    .font(theme.appFont(size: 13, weight: .medium))
                    .foregroundColor(ThemeManager.secondaryText)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Text(loc.t("reply"))
                .font(theme.appFont(size: 14, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            
            Spacer()
            
            Button(action: submitReply) {
                HStack(spacing: 6) {
                    if state.isSending {
                        LoadingIndicator(compactHeight: 16, tint: ThemeManager.onAccent)
                    }
                    Text(loc.t("post_reply"))
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.onAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(canSend ? ThemeManager.accent : ThemeManager.accent.opacity(0.4))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
    
    private var originalTweetSnippet: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                CachedAsyncImage(urlString: tweet.author.avatarUrl)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ThemeManager.border, lineWidth: 0.5))
                
                Rectangle()
                    .fill(ThemeManager.divider)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(tweet.author.name)
                        .font(theme.appFont(size: 13.5, weight: .bold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(1)
                    
                    Text(tweet.author.formattedHandle)
                        .font(theme.appFont(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(1)
                    
                    Text("·")
                        .font(theme.appFont(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                    
                    Text(tweet.relativeTime)
                        .font(theme.appFont(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                }
                
                if !tweet.cleanText.isEmpty {
                    Text(tweet.cleanText)
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.primaryText.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Text(loc.t("replying_to").replacingOccurrences(of: "{author}", with: tweet.author.formattedHandle))
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.accent)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
    
    private var composerInputRow: some View {
        HStack(alignment: .top, spacing: 10) {
            CurrentUserAvatar(size: 34)
                .padding(.top, 2)
            
            TextField(
                loc.t("reply_placeholder"),
                text: $state.replyText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(ThemeManager.primaryText)
            .lineLimit(5...10)
            .returnStartsNewLine()
            .frame(minHeight: 110, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.red)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var progressRatio: CGFloat {
        let count = Double(state.replyText.count)
        let limit = Double(characterLimit)
        return CGFloat(min(max(count / limit, 0.0), 1.0))
    }
    
    private var progressColor: Color {
        if remainingCharacters < 0 {
            return Color.red
        } else if remainingCharacters <= 20 {
            return Color.orange
        } else {
            return ThemeManager.accent
        }
    }
    
    private var bottomControlsBar: some View {
        HStack(spacing: 8) {
            ComposerAttachButton(isDisabled: state.isSending, action: chooseMedia)
            
            Text("⌘ + Enter")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeManager.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ThemeManager.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Spacer()
            
            HStack(spacing: 6) {
                if remainingCharacters <= 20 {
                    Text("\(remainingCharacters)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(remainingCharacters < 0 ? .red : .orange)
                }
                
                Circle()
                    .stroke(ThemeManager.divider, lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .trim(from: 0, to: progressRatio)
                            .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ThemeManager.background)
    }
    
    private func submitReply() {
        let textToSend = state.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty || !state.attachments.isEmpty else { return }
        
        state.isSending = true
        state.errorMessage = nil
        let attachments = state.attachments
        
        Task { @MainActor in
            let mediaIds: [String]
            do {
                mediaIds = try await MediaAttachments.upload(attachments) { state.uploadStatus = $0 }
            } catch {
                state.isSending = false
                state.errorMessage = error.localizedDescription
                return
            }
            
            TimelineViewModel.shared.postReply(to: tweet, text: textToSend, mediaIds: mediaIds) { result in
                DispatchQueue.main.async {
                    self.state.isSending = false
                    switch result {
                    case .success:
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_ReplyPosted"), object: nil,
                                                        userInfo: ["targetId": self.tweet.id])
                        self.dismiss()
                    case .failure(let err):
                        self.state.errorMessage = err.localizedDescription
                    }
                }
            }
        }
    }
}

// Extension to safely hide TextEditor scroll content background across macOS versions
private extension View {
    @ViewBuilder
    func scrollContentBackgroundHidden() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
