//
//  ComposerMedia.swift
//  Tweetintosh - Headless Data-driven Client
//
//  What the post and reply composers share for attaching media: the button, the strip of thumbnails, and adding and
//  uploading the files.
//

import SwiftUI

struct ComposerAttachButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 12, weight: .medium))
                    Text(loc.t("attach_media"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(ThemeManager.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .disabled(isDisabled)

            Text("⌥ + A")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeManager.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ThemeManager.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct ComposerAttachmentStrip: View {
    @Binding var attachments: [ComposerAttachment]
    let isDisabled: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
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
                        .buttonStyle(.target)
                        .disabled(isDisabled)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 90)
    }

    private func remove(_ attachment: ComposerAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if attachment.isTemporaryCopy { try? FileManager.default.removeItem(at: attachment.url) }
    }
}

extension MediaAttachments {
    // Adds chosen, pasted or dropped files, checking each against the supported formats and X's limits. Answers with
    // what went wrong, if anything did.
    static func add(_ urls: [URL], to attachments: inout [ComposerAttachment], pasted: Bool) -> String? {
        var problem: String?
        for url in urls {
            do {
                var attachment = try makeAttachment(from: url)
                // A pasted image only exists as the temporary file made for it, which goes with the attachment
                if pasted && !attachment.isTemporaryCopy { attachment = attachment.asTemporaryCopy() }
                do {
                    try validateAdding(attachment, to: attachments)
                } catch {
                    if attachment.isTemporaryCopy { try? FileManager.default.removeItem(at: attachment.url) }
                    throw error
                }
                attachments.append(attachment)
            } catch {
                if pasted { try? FileManager.default.removeItem(at: url) }
                problem = error.localizedDescription
            }
        }
        return problem
    }

    // X needs every file before the post that uses them is created
    // `progress` is the share of all the files sent so far, from 0 to 1, for the composer's progress bar
    @MainActor
    static func upload(_ attachments: [ComposerAttachment], status: (String?) -> Void,
                       progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> [String] {
        defer { status(nil) }
        var mediaIds: [String] = []
        let count = Double(max(attachments.count, 1))
        for (index, attachment) in attachments.enumerated() {
            status(LocalizationManager.shared.format("media_uploading", ["current": String(index + 1), "total": String(attachments.count)]))
            progress(Double(index) / count)
            mediaIds.append(try await APIClient.shared.uploadMedia(attachment) { fraction in
                DispatchQueue.main.async { progress((Double(index) + fraction) / count) }
            })
        }
        progress(1)
        return mediaIds
    }
}

// MARK: - Sending Progress

// Along the line under a composer's title bar while a post is on its way, always in that one place. It fills as the
// attached files upload; with nothing to upload, how long X takes can't be known, so it shows the system's moving bar
// instead. The Post button itself only dims meanwhile.
struct ComposerSendingBar: View {
    let isSending: Bool
    // The share of the attached files uploaded, or nil when there are none
    let progress: Double?

    var body: some View {
        ZStack(alignment: .top) {
            Divider()
                .background(ThemeManager.divider)
            if isSending {
                Group {
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(ThemeManager.accent)
                .transition(.opacity)
                .accessibilityLabel(LocalizationManager.shared.t("posting"))
            }
        }
        .frame(height: 1, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: isSending)
    }
}
