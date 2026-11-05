//
//  TweetComposerSheet.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

final class TweetComposerState: ObservableObject {
    @Published var text: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String? = nil
    @Published var attachments: [ComposerAttachment] = []
    // What the upload is up to ("Uploading 2 of 3…"), shown while posting
    @Published var uploadStatus: String? = nil
}

struct TweetComposerSheet: View {
    var quotedTweet: Tweet? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @StateObject private var state = TweetComposerState()
    
    private let characterLimit = 280
    
    private var remainingCharacters: Int {
        characterLimit - state.text.count
    }
    
    private var canSend: Bool {
        let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || !state.attachments.isEmpty) && remainingCharacters >= 0 && !state.isSending
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            
            Divider()
                .background(ThemeManager.divider)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    composerInputRow
                    
                    if !state.attachments.isEmpty {
                        ComposerAttachmentStrip(attachments: $state.attachments, isDisabled: state.isSending)
                    }
                    
                    if let quoted = quotedTweet {
                        QuotedTweetCard(tweet: quoted, isInteractive: false)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    
                    if let status = state.uploadStatus {
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundColor(ThemeManager.secondaryText)
                            .padding(.horizontal, 16)
                    }
                    
                    if let error = state.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.top, 12)
            }
            .onAppear { WebKitWriteChannel.shared.warmUp() }
            
            Divider()
                .background(ThemeManager.divider)
            
            bottomControlsBar
        }
        .frame(width: 540, height: (quotedTweet != nil ? 430 : 320) + (state.attachments.isEmpty ? 0 : 110))
        .background(ThemeManager.background)
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
            state.attachments.filter(\.isTemporaryCopy).forEach { try? FileManager.default.removeItem(at: $0.url) }
        }
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack {
            Button(action: {
                NavigationManager.shared.dismissComposer()
                dismiss()
            }) {
                Text(loc.t("cancel"))
                    .font(theme.appFont(size: 13, weight: .medium))
                    .foregroundColor(ThemeManager.secondaryText)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Text(quotedTweet != nil ? loc.t("quote_tweet") : loc.t("new_post"))
                .font(theme.appFont(size: 14, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            
            Spacer()
            
            Button(action: submitPost) {
                HStack(spacing: 6) {
                    if state.isSending {
                        LoadingIndicator(compactHeight: 16, tint: ThemeManager.onAccent)
                    }
                    Text(loc.t("post_action"))
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.onAccent)
                }
                .padding(.horizontal, 16)
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
    
    private var composerInputRow: some View {
        HStack(alignment: .top, spacing: 12) {
            CurrentUserAvatar(size: 36)
                .padding(.top, 2)
            
            TextField(
                quotedTweet != nil ? loc.t("quote_placeholder") : loc.t("post_placeholder"),
                text: $state.text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(theme.appFont(size: 14.5))
            .foregroundColor(ThemeManager.primaryText)
            .lineLimit(quotedTweet != nil ? 4...8 : 7...14)
            .returnStartsNewLine()
            .frame(minHeight: quotedTweet != nil ? 90 : 160, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
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
        .padding(.top, 4)
    }
    
    private var progressRatio: CGFloat {
        let count = Double(state.text.count)
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
    
    // MARK: - Attachments
    
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
    
    private func submitPost() {
        let textToSend = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty || !state.attachments.isEmpty else { return }
        
        state.isSending = true
        state.errorMessage = nil
        let attachments = state.attachments
        
        Task { @MainActor in
            // Upload the media first; the post is created once X has every file
            var mediaIds: [String] = []
            do {
                mediaIds = try await MediaAttachments.upload(attachments) { state.uploadStatus = $0 }
            } catch {
                state.isSending = false
                state.uploadStatus = nil
                state.errorMessage = error.localizedDescription
                return
            }
            state.uploadStatus = nil
            
            TimelineViewModel.shared.postTweet(text: textToSend, quoting: quotedTweet, mediaIds: mediaIds) { result in
                DispatchQueue.main.async {
                    self.state.isSending = false
                    switch result {
                    case .success:
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        NavigationManager.shared.dismissComposer()
                        self.dismiss()
                    case .failure(let err):
                        self.state.errorMessage = err.localizedDescription
                    }
                }
            }
        }
    }
}

// A multi-line TextField on macOS treats Return as "finished" and only starts a new line on Option+Return, which nobody
// would guess in a box for writing posts. Return and Shift+Return start one here; Command+Return still reaches the
// post button.
extension View {
    func returnStartsNewLine() -> some View {
        // The keypad's Enter key is a separate character from Return
        onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
            guard !press.modifiers.contains(.command),
                  let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                  // Return is confirming a Chinese or Japanese word still being composed
                  !editor.hasMarkedText() else { return .ignored }
            editor.insertNewlineIgnoringFieldEditor(nil)
            return .handled
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
