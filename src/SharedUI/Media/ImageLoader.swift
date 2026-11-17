//
//  ImageLoader.swift
//  Tweetintosh
//
//  The shared image path: memory/disk cache lookups, one download per address, and the SwiftUI view that shows it.
//

import SwiftUI
import AppKit

// MARK: - Image Memory & Disk Cache
final class ImageCache {
    static let shared = ImageCache()

    private init() {}

    func image(for url: String) -> NSImage? {
        MediaCacheManager.shared.image(for: url)
    }

    func setImage(_ image: NSImage, for url: String) {
        MediaCacheManager.shared.storeImage(image, rawData: nil, for: url)
    }

    func prefetch(urls: [String]) {
        MediaCacheManager.shared.prefetchImages(urls: urls)
    }
}

// MARK: - Image Loader (Sync Cache Hit & Offloaded Disk/Network)
final class ImageLoader: ObservableObject {
    // What to show, and the display box it was decoded for. A reused table cell keeps its loader for the next post, so
    // the two travel together: a box that no longer matches means the picture belongs to someone else.
    private struct Request: Equatable {
        let url: String
        let targetSize: CGSize?

        // Display box in device pixels; nil decodes at full resolution.
        var pixelSize: CGSize? {
            guard let size = targetSize, size.width > 0, size.height > 0 else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        }
    }

    private struct Flight {
        let id: UUID
        let request: Request
    }

    // Published as a CGImage so SwiftUI hands the decoded bitmap straight to Core Animation (no NSImage rep lookup).
    @Published private var loadedImage: CGImage?
    // All loader state stays on the main thread; background work only holds immutable requests and weak references.
    private var shown: Request?
    private var current: Request?
    private var inFlight: Flight?
    private var pendingData: (flightID: UUID, url: String, token: UUID)?
    private var resizeWork: DispatchWorkItem?
    private var resizeID: UUID?
    private var releaseID: UUID?

    init(urlString: String?, targetSize: CGSize? = nil) {
        guard let urlString = urlString else { return }
        let request = Request(url: urlString, targetSize: targetSize)
        current = request
        // Immediate frame-0 hit if already decoded in memory.
        if let mem = MediaCacheManager.shared.memoryImage(for: urlString, targetPixelSize: request.pixelSize) {
            loadedImage = Self.cgImage(of: mem)
            shown = request
        }
    }

    deinit {
        resizeWork?.cancel()
        if let pendingData {
            MediaCacheManager.shared.cancelImageData(for: pendingData.url, token: pendingData.token)
        }
    }

    // The picture for this address, or nil for the placeholder. Asked while the body is evaluated, so a reused cell never
    // shows the previous post's picture for even one frame, and so it must not change any published state.
    func image(urlString: String?, targetSize: CGSize?) -> CGImage? {
        guard let urlString = urlString else { return nil }
        let request = Request(url: urlString, targetSize: targetSize)
        if shown == request { return loadedImage }
        if let exact = MediaCacheManager.shared.memoryImage(for: urlString, targetPixelSize: request.pixelSize).flatMap(Self.cgImage(of:)) {
            return exact
        }
        // The same picture at another size (its tile is being resized) is drawn scaled until the right size is ready.
        return shown?.url == urlString ? loadedImage : nil
    }

    func load(urlString: String?, targetSize: CGSize?) {
        releaseID = nil
        guard let urlStr = urlString else {
            stop()
            return
        }
        let request = Request(url: urlStr, targetSize: targetSize)
        if current?.url != urlStr {
            cancelPendingData()
            // This loader has been handed another post: its picture is no longer something any view can ask for.
            loadedImage = nil
            shown = nil
        }
        current = request
        resizeWork?.cancel()
        resizeWork = nil
        resizeID = nil
        let targetPixelSize = request.pixelSize

        // A memory hit also retires any older subscription or decode for this loader.
        if let mem = MediaCacheManager.shared.memoryImage(for: urlStr, targetPixelSize: targetPixelSize) {
            cancelPendingData()
            if shown != request || loadedImage == nil {
                loadedImage = Self.cgImage(of: mem)
                shown = request
            }
            return
        }

        // Keep drawing the previous size during a column animation, then decode once the size has settled.
        if shown?.url == urlStr, loadedImage != nil {
            let id = UUID()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.resizeID == id, self.current == request else { return }
                self.resizeWork = nil
                self.resizeID = nil
                self.fetch(request)
            }
            resizeWork = work
            resizeID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        fetch(request)
    }

    func stop() {
        current = nil
        cancelPendingData()
        // A page leaves with its transition still on screen, and a table cell outlives the row it showed. Keep the
        // picture through the transition, then let it go unless the view came back; coming back is a cache hit.
        let id = UUID()
        releaseID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.releaseID == id, self.current == nil else { return }
            self.releaseID = nil
            self.loadedImage = nil
            self.shown = nil
        }
    }

    private func fetch(_ request: Request) {
        guard inFlight?.request != request else { return }
        // A size change can use the same download; choose its decode size when the bytes arrive.
        if pendingData?.url == request.url { return }
        cancelPendingData()
        let flight = Flight(id: UUID(), request: request)
        inFlight = flight
        let targetPixelSize = request.pixelSize

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = MediaCacheManager.shared.diskImage(for: request.url, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inFlight?.id == flight.id else { return }
                if let image {
                    self.finish(flight, image: image)
                } else {
                    self.subscribe(flight)
                }
            }
        }
    }

    private func subscribe(_ flight: Flight) {
        // Register and save the token in one main-thread turn, so stop/reuse cannot lose a background registration.
        guard inFlight?.id == flight.id, current?.url == flight.request.url else { return }
        let urlStr = flight.request.url
        let token = MediaCacheManager.shared.fetchImageData(for: urlStr) { [weak self] data in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inFlight?.id == flight.id, let request = self.current else { return }
                if self.pendingData?.flightID == flight.id { self.pendingData = nil }
                let decodeFlight = Flight(id: flight.id, request: request)
                self.inFlight = decodeFlight
                let targetPixelSize = request.pixelSize
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let image = data.flatMap {
                        MediaCacheManager.shared.storeImageData($0, for: urlStr, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:))
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.finish(decodeFlight, image: image)
                    }
                }
            }
        }
        if let token {
            pendingData = (flight.id, urlStr, token)
        }
    }

    // Invalidate work even when the disk lookup has not registered a data subscription yet.
    private func cancelPendingData() {
        resizeWork?.cancel()
        resizeWork = nil
        resizeID = nil
        inFlight = nil
        if let pending = pendingData {
            pendingData = nil
            MediaCacheManager.shared.cancelImageData(for: pending.url, token: pending.token)
        }
    }

    private func finish(_ flight: Flight, image: CGImage?) {
        guard inFlight?.id == flight.id else { return }
        inFlight = nil
        guard current == flight.request else {
            if let current, current.url == flight.request.url, resizeWork == nil { fetch(current) }
            return
        }
        guard let image else { return }
        loadedImage = image
        shown = flight.request
    }

    // Cache images are NSImage(cgImage:) wrappers, so this returns the backing CGImage without redrawing.
    private static func cgImage(of image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage: View {
    private struct LoadKey: Equatable {
        let url: String?
        let targetSize: CGSize?
    }

    let urlString: String?
    var placeholderColor: Color = Color(white: 0.08)
    var contentMode: ContentMode = .fill
    let targetSize: CGSize?

    @StateObject private var loader: ImageLoader
    @Environment(\.isMeasuringRow) private var isMeasuringRow

    // targetSize (points): pass the on-screen box to decode a downsampled bitmap instead of the full image
    init(urlString: String?, placeholderColor: Color = Color(white: 0.08), contentMode: ContentMode = .fill, targetSize: CGSize? = nil) {
        self.urlString = urlString
        self.placeholderColor = placeholderColor
        self.contentMode = contentMode
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(urlString: urlString, targetSize: targetSize))
    }

    var body: some View {
        if isMeasuringRow {
            // A measured row only needs the picture's place, and the placeholder already gives it one. Loading here
            // would touch the caches and the network for a view nobody sees, and hand this same image view a new
            // address for every post measured, which SwiftUI reports as the load key updating multiple times a frame.
            Rectangle()
                .fill(placeholderColor)
        } else {
            ZStack {
                if let image = loader.image(urlString: urlString, targetSize: targetSize) {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    // Plain placeholder: a ProgressView here is an AppKit NSProgressIndicator per loading tile, and
                    // creating/animating one for every image scrolling into view caused visible scroll hitches.
                    Rectangle()
                        .fill(placeholderColor)
                }
            }
            .onAppear {
                loader.load(urlString: urlString, targetSize: targetSize)
            }
            .onDisappear {
                loader.stop()
            }
            // The address can arrive after the view does (a profile opened from an @mention knows only the handle until
            // X has answered), and a reused table cell is handed a different post, so a new address is loaded too
            .onChange(of: LoadKey(url: urlString, targetSize: targetSize)) {
                loader.load(urlString: urlString, targetSize: targetSize)
            }
        }
    }
}
