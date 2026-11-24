//
//  MediaAttachments.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Picking photos, GIFs and videos for a post: the file picker only offers formats X accepts, and the limits X
//  applies to a post (up to 20 photos, or one GIF, or one video) are checked before anything is uploaded.
//

import AppKit
import AVFoundation
import ImageIO
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

extension ComposerAttachment {
    // The same attachment, flagged so its file is removed with it (used for pasted images saved to a temporary file)
    func asTemporaryCopy() -> ComposerAttachment {
        ComposerAttachment(url: url, kind: kind, mimeType: mimeType, byteCount: byteCount, thumbnail: thumbnail, isTemporaryCopy: true)
    }
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
            return loc.format("media_too_many", ["max": String(MediaAttachments.maxImages)])
        case .mixedKinds:
            return loc.format("media_mixed", ["max": String(MediaAttachments.maxImages)])
        case .unreadable(let name):
            return loc.format("media_unreadable", ["name": name])
        }
    }
}

enum MediaAttachments {
    // The formats X takes for a post. HEIC photos are accepted too and converted to JPEG on the way in.
    static let pickerTypes: [UTType] = [.jpeg, .png, .gif, .webP, .mpeg4Movie, .quickTimeMovie, .heic]
    static let maxImages = 20

    // Shows the file picker (formats limited to the supported ones) and hands back what was chosen
    @MainActor
    static func pick(parent: NSWindow?, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = LocalizationManager.shared.t("attach_media")
        panel.allowedContentTypes = pickerTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // A free-standing panel stays key after it closes, leaving the window that opened it deaf to the keyboard
        let opener = NSApp.keyWindow
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            if parent == nil { opener?.makeKey() }
            completion(response == .OK ? panel.urls : [])
        }
        if let parent = parent {
            panel.beginSheetModal(for: parent, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    // MARK: Pasting

    // Files copied in Finder, or an image copied from anywhere (a screenshot, "Copy Image" in a browser). Plain text,
    // even alongside an image, stays a normal paste unless the text is just the image's address.
    static func pastedMedia(from pasteboard: NSPasteboard) -> [URL] {
        switch pastable(on: pasteboard) {
        case .files(let urls):
            return urls
        case .image(let image):
            guard let png = pngData(from: image) else { return [] }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pasted-\(UUID().uuidString.prefix(6)).png")
            guard (try? png.write(to: url)) != nil else { return [] }
            return [url]
        case nil:
            return []
        }
    }

    // Asked on every Command+V, so it only looks: the temporary file is made once the paste really happens
    static func hasPastableMedia(_ pasteboard: NSPasteboard) -> Bool {
        pastable(on: pasteboard) != nil
    }

    private enum Pastable {
        case files([URL])
        case image(NSImage)
    }

    private static func pastable(on pasteboard: NSPasteboard) -> Pastable? {
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let supported = fileURLs.filter { url in
            UTType(filenameExtension: url.pathExtension.lowercased()).map { type in pickerTypes.contains { type.conforms(to: $0) } } ?? false
        }
        if !supported.isEmpty { return .files(supported) }
        guard fileURLs.isEmpty else { return nil }

        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
           !(text.hasPrefix("http") && !text.contains(" ") && !text.contains("\n")) { return nil }
        return NSImage(pasteboard: pasteboard).map(Pastable.image)
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
            return try makeHEICAttachment(from: url, name: name)
        }
        if type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .webP) {
            if size <= AttachmentKind.image.maxBytes {
                let mime = type.conforms(to: .png) ? "image/png" : (type.conforms(to: .webP) ? "image/webp" : "image/jpeg")
                return ComposerAttachment(url: url, kind: .image, mimeType: mime, byteCount: size,
                                          thumbnail: NSImage(contentsOf: url), isTemporaryCopy: false)
            }
            guard ThemeManager.shared.autoCompressImages else {
                throw MediaAttachmentError.tooLarge(name, AttachmentKind.image.maxBytes)
            }
            return try compressedAttachment(from: url, name: name, maxBytes: AttachmentKind.image.maxBytes)
        }
        throw MediaAttachmentError.unsupported(name)
    }

    // A post takes up to 20 photos, or a single GIF, or a single video: never a mixture
    static func validateAdding(_ new: ComposerAttachment, to current: [ComposerAttachment]) throws {
        guard let first = current.first else { return }
        guard first.kind == .image, new.kind == .image else { throw MediaAttachmentError.mixedKinds }
        guard current.count < maxImages else { throw MediaAttachmentError.tooManyImages }
    }

    // MARK: Image Compression

    // HEIC is always transcoded to JPEG because X does not accept HEIC directly; when the result still exceeds X's
    // limit, fall through to the same low-loss compression ladder if auto-compression is enabled.
    private static func makeHEICAttachment(from url: URL, name: String) throws -> ComposerAttachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = decodedImage(from: source, maxPixelSize: nil),
              let jpeg = encode(image, as: .jpeg, quality: 0.92) else {
            throw MediaAttachmentError.unreadable(name)
        }
        if jpeg.count <= AttachmentKind.image.maxBytes {
            let copy = temporaryFileURL(baseName: url.deletingPathExtension().lastPathComponent, ext: "jpg")
            try jpeg.write(to: copy)
            return ComposerAttachment(url: copy, kind: .image, mimeType: "image/jpeg", byteCount: jpeg.count,
                                      thumbnail: NSImage(cgImage: image, size: .zero), isTemporaryCopy: true)
        }
        guard ThemeManager.shared.autoCompressImages else {
            throw MediaAttachmentError.tooLarge(name, AttachmentKind.image.maxBytes)
        }
        return try compressedAttachment(from: url, name: name, maxBytes: AttachmentKind.image.maxBytes)
    }

    // Re-encodes an oversized static image with ImageIO so colour profiles (such as Display P3) and EXIF orientation
    // stay intact. Keeps full resolution first and only steps down dimensions when quality alone cannot meet the limit.
    private static func compressedAttachment(from url: URL, name: String, maxBytes: Int) throws -> ComposerAttachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let fullImage = decodedImage(from: source, maxPixelSize: nil) else {
            throw MediaAttachmentError.unreadable(name)
        }

        let originalMaxEdge = max(fullImage.width, fullImage.height)
        let transparent = hasTransparency(fullImage)
        var encoded: (data: Data, mimeType: String, ext: String)?

        if transparent {
            // Preserve transparency when possible: re-encode PNG at full size first, then step down resolution.
            if let png = encode(fullImage, as: .png, quality: nil), png.count <= maxBytes {
                encoded = (png, "image/png", "png")
            } else {
                for maxEdge in [4096, 3072, 2560, 2048, 1600, 1280] where maxEdge < originalMaxEdge {
                    if let scaled = decodedImage(from: source, maxPixelSize: maxEdge),
                       let png = encode(scaled, as: .png, quality: nil),
                       png.count <= maxBytes {
                        encoded = (png, "image/png", "png")
                        break
                    }
                }
            }
        }

        if encoded == nil {
            let jpegSource = transparent ? flattenOntoWhite(fullImage) : fullImage
            for quality in [0.92, 0.86, 0.80, 0.74] {
                if let jpeg = encode(jpegSource, as: .jpeg, quality: quality), jpeg.count <= maxBytes {
                    encoded = (jpeg, "image/jpeg", "jpg")
                    break
                }
            }
        }

        if encoded == nil {
            for maxEdge in [4096, 3072, 2560, 2048, 1600] where maxEdge < originalMaxEdge {
                guard let scaled = decodedImage(from: source, maxPixelSize: maxEdge) else { continue }
                let jpegSource = transparent ? flattenOntoWhite(scaled) : scaled
                for quality in [0.88, 0.80, 0.72] {
                    if let jpeg = encode(jpegSource, as: .jpeg, quality: quality), jpeg.count <= maxBytes {
                        encoded = (jpeg, "image/jpeg", "jpg")
                        break
                    }
                }
                if encoded != nil { break }
            }
        }

        if encoded == nil {
            let fallbackImage: CGImage
            if originalMaxEdge > 2048, let scaled = decodedImage(from: source, maxPixelSize: 2048) {
                fallbackImage = transparent ? flattenOntoWhite(scaled) : scaled
            } else {
                fallbackImage = transparent ? flattenOntoWhite(fullImage) : fullImage
            }
            for quality in [0.65, 0.55] {
                if let jpeg = encode(fallbackImage, as: .jpeg, quality: quality), jpeg.count <= maxBytes {
                    encoded = (jpeg, "image/jpeg", "jpg")
                    break
                }
            }
        }

        guard let result = encoded else {
            throw MediaAttachmentError.tooLarge(name, maxBytes)
        }

        let copy = temporaryFileURL(baseName: url.deletingPathExtension().lastPathComponent, ext: result.ext)
        try result.data.write(to: copy)
        return ComposerAttachment(url: copy, kind: .image, mimeType: result.mimeType, byteCount: result.data.count,
                                  thumbnail: NSImage(cgImage: fullImage, size: .zero), isTemporaryCopy: true)
    }

    private static func temporaryFileURL(baseName: String, ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString.prefix(6)).\(ext)")
    }

    // Decodes with the EXIF orientation transform baked in so rotated camera photos remain upright after re-encoding.
    private static func decodedImage(from source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        let targetMax: Int
        if let maxPixelSize = maxPixelSize {
            targetMax = maxPixelSize
        } else if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int,
                  max(width, height) > 0 {
            targetMax = max(width, height)
        } else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetMax
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality = quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        // macOS screenshots are saved as RGBA PNGs even when every pixel is opaque, so sample the alpha channel in a
        // small RGBA bitmap to distinguish genuine transparency from an unused alpha byte.
        let width = min(image.width, 512)
        let height = min(image.height, 512)
        guard width > 0, height > 0 else { return false }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.setBlendMode(.copy)
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for offset in stride(from: 3, to: rgba.count, by: 4) where rgba[offset] < 255 {
            return true
        }
        return false
    }

    // Composites a transparent image onto white before JPEG fallback so transparent regions do not turn black.
    private static func flattenOntoWhite(_ image: CGImage) -> CGImage {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func videoThumbnail(_ url: URL) -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
