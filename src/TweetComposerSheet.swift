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
                        attachmentStrip
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
            
            Divider()
                .background(ThemeManager.divider)
            
            bottomControlsBar
        }
        .frame(width: 540, height: (quotedTweet != nil ? 430 : 320) + (state.attachments.isEmpty ? 0 : 110))
        .background(ThemeManager.background)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_AttachMedia"))) { _ in
            chooseMedia()
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ThemeManager.secondaryText)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Text(quotedTweet != nil ? loc.t("quote_tweet") : loc.t("new_post"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ThemeManager.primaryText)
            
            Spacer()
            
            Button(action: submitPost) {
                HStack(spacing: 6) {
                    if state.isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.65)
                            .frame(width: 14, height: 14)
                    }
                    Text(loc.t("post_action"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
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
            .font(.system(size: 14.5))
            .foregroundColor(ThemeManager.primaryText)
            .lineLimit(quotedTweet != nil ? 4...8 : 7...14)
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
            Button(action: chooseMedia) {
                HStack(spacing: 5) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 12, weight: .medium))
                    Text(loc.t("attach_media"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(ThemeManager.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isSending)
            
            Text("⌥ + A")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeManager.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ThemeManager.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
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
    
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(state.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = attachment.thumbnail {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(ThemeManager.cardBackground)
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            if attachment.kind != .image {
                                Text(attachment.kind == .gif ? "GIF" : "▶")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(5)
                            }
                        }
                        
                        Button {
                            remove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isSending)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 90)
    }
    
    private func chooseMedia() {
        guard !state.isSending else { return }
        MediaAttachments.pick(parent: nil) { urls in
            state.errorMessage = nil
            for url in urls {
                do {
                    let attachment = try MediaAttachments.makeAttachment(from: url)
                    do {
                        try MediaAttachments.validateAdding(attachment, to: state.attachments)
                    } catch {
                        if attachment.isTemporaryCopy { try? FileManager.default.removeItem(at: attachment.url) }
                        throw error
                    }
                    state.attachments.append(attachment)
                } catch {
                    state.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func remove(_ attachment: ComposerAttachment) {
        state.attachments.removeAll { $0.id == attachment.id }
        if attachment.isTemporaryCopy { try? FileManager.default.removeItem(at: attachment.url) }
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
                for (index, attachment) in attachments.enumerated() {
                    state.uploadStatus = loc.format("media_uploading", ["current": String(index + 1), "total": String(attachments.count)])
                    mediaIds.append(try await APIClient.shared.uploadMedia(attachment))
                }
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
