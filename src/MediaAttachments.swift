//
//  MediaAttachments.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Picking photos, GIFs and videos for a post: the file picker only offers formats X accepts, and the limits X
//  applies to a post (up to 4 photos, or one GIF, or one video) are checked before anything is uploaded.
//

import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum AttachmentKind {
    case image, gif, video

    // The upload category X's own apps use for each kind of media
    var uploadCategory: String {
        switch self {
        case .image: return "tweet_image"
        case .gif: return "tweet_gif"
        case .video: return "tweet_video"
        }
    }

    var maxBytes: Int {
        switch self {
        case .image: return 5 * 1024 * 1024
        case .gif: return 15 * 1024 * 1024
        case .video: return 512 * 1024 * 1024
        }
    }
}

struct ComposerAttachment: Identifiable {
    let id = UUID()
    let url: URL
    let kind: AttachmentKind
    let mimeType: String
    let byteCount: Int
    let thumbnail: NSImage?
    // A converted copy made for the upload (HEIC photos are sent as JPEG); removed with the attachment
    let isTemporaryCopy: Bool
}

enum MediaAttachmentError: LocalizedError {
    case unsupported(String)
    case tooLarge(String, Int)
    case tooManyImages
    case mixedKinds
    case unreadable(String)

    var errorDescription: String? {
        let loc = LocalizationManager.shared
        switch self {
        case .unsupported(let name):
            return loc.format("media_unsupported", ["name": name])
        case .tooLarge(let name, let limit):
            let mb = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return loc.format("media_too_large", ["name": name, "limit": mb])
        case .tooManyImages:
            return loc.t("media_too_many")
        case .mixedKinds:
            return loc.t("media_mixed")
        case .unreadable(let name):
            return loc.format("media_unreadable", ["name": name])
        }
    }
}

enum MediaAttachments {
    // The formats X takes for a post. HEIC photos are accepted too and converted to JPEG on the way in.
    static let pickerTypes: [UTType] = [.jpeg, .png, .gif, .webP, .mpeg4Movie, .quickTimeMovie, .heic]
    static let maxImages = 4

    // Shows the file picker (formats limited to the supported ones) and hands back what was chosen
    @MainActor
    static func pick(parent: NSWindow?, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = LocalizationManager.shared.t("attach_media")
        panel.allowedContentTypes = pickerTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.urls : [])
        }
        if let parent = parent {
            panel.beginSheetModal(for: parent, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    // Checks the file against the supported formats and X's size limits and prepares it for upload
    static func makeAttachment(from url: URL) throws -> ComposerAttachment {
        let name = url.lastPathComponent
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            throw MediaAttachmentError.unsupported(name)
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if type.conforms(to: .gif) {
            guard size <= AttachmentKind.gif.maxBytes else { throw MediaAttachmentError.tooLarge(name, AttachmentKind.gif.maxBytes) }
            return ComposerAttachment(url: url, kind: .gif, mimeType: "image/gif", byteCount: size,
                                      thumbnail: NSImage(contentsOf: url), isTemporaryCopy: false)
        }
        if type.conforms(to: .movie) || type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie) {
            guard type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie) else { throw MediaAttachmentError.unsupported(name) }
            guard size <= AttachmentKind.video.maxBytes else { throw MediaAttachmentError.tooLarge(name, AttachmentKind.video.maxBytes) }
            let mime = type.conforms(to: .quickTimeMovie) ? "video/quicktime" : "video/mp4"
            return ComposerAttachment(url: url, kind: .video, mimeType: mime, byteCount: size,
                                      thumbnail: videoThumbnail(url), isTemporaryCopy: false)
        }
        if type == .heic || type.identifier == "public.heif" {
            guard let image = NSImage(contentsOf: url), let jpeg = jpegData(from: image) else { throw MediaAttachmentError.unreadable(name) }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(UUID().uuidString.prefix(6)).jpg")
            try jpeg.write(to: copy)
            guard jpeg.count <= AttachmentKind.image.maxBytes else {
                try? FileManager.default.removeItem(at: copy)
                throw MediaAttachmentError.tooLarge(name, AttachmentKind.image.maxBytes)
            }
            return ComposerAttachment(url: copy, kind: .image, mimeType: "image/jpeg", byteCount: jpeg.count,
                                      thumbnail: image, isTemporaryCopy: true)
        }
        if type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .webP) {
            guard size <= AttachmentKind.image.maxBytes else { throw MediaAttachmentError.tooLarge(name, AttachmentKind.image.maxBytes) }
            let mime = type.conforms(to: .png) ? "image/png" : (type.conforms(to: .webP) ? "image/webp" : "image/jpeg")
            return ComposerAttachment(url: url, kind: .image, mimeType: mime, byteCount: size,
                                      thumbnail: NSImage(contentsOf: url), isTemporaryCopy: false)
        }
        throw MediaAttachmentError.unsupported(name)
    }

    // A post takes up to four photos, or a single GIF, or a single video: never a mixture
    static func validateAdding(_ new: ComposerAttachment, to current: [ComposerAttachment]) throws {
        guard let first = current.first else { return }
        guard first.kind == .image, new.kind == .image else { throw MediaAttachmentError.mixedKinds }
        guard current.count < maxImages else { throw MediaAttachmentError.tooManyImages }
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    private static func videoThumbnail(_ url: URL) -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
