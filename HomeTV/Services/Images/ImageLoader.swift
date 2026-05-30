import UIKit
import ImageIO

/// Loads, downsamples, and caches remote images for the TV UI.
///
/// `AsyncImage` is the wrong tool on tvOS: it doesn't cache decoded images, cancels in-flight
/// requests when a view scrolls off, and hands SwiftUI a full-resolution image that Core Animation
/// decodes on the main thread at draw time (a 4K backdrop is ~33 MB of RGBA → a visible hitch).
///
/// This loader instead:
/// - downsamples off the main thread to the exact point size each call site needs,
/// - caches the decoded `UIImage` in an `NSCache` (thread-safe, evicts under memory pressure), and
/// - coalesces concurrent requests for the same key so duplicate posters fetch + decode once.
///
/// Raw bytes are cached separately by `URLCache.shared` (configured at launch in `HomeTVApp`),
/// so even a cache miss here usually avoids the network.
actor ImageLoader {
    static let shared = ImageLoader()

    /// Identifies a decoded image by source URL *and* the size it was decoded for — the same poster
    /// rendered at thumbnail vs. hero size are different cache entries.
    private struct Key: Hashable {
        let url: URL
        let maxPixel: Int

        var cacheKey: NSString { "\(url.absoluteString)|\(maxPixel)" as NSString }
    }

    // NSCache is internally thread-safe, so the decoded-image cache can be read from a nonisolated
    // context (see `cachedImage`) as well as from the actor.
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [Key: Task<UIImage, Error>] = [:]

    /// Decode at up to 2× the requested point size for sharpness on 4K. Baked in (rather than read
    /// from the view's display scale) so the cache key is scale-independent and a view can peek the
    /// cache synchronously before its environment is available.
    private static let renderScale: CGFloat = 2

    init() {
        // Dedicated session so image traffic uses the shared on-disk URLCache. The Stremio JSON
        // client stays ephemeral on purpose; these are different caching needs.
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = .shared
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        // ~120 MB of decoded pixels; NSCache also drops everything on a memory warning.
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    /// Synchronous peek into the decoded-image cache so a view can show an already-decoded image on
    /// its very first frame (no placeholder flash). Safe from any thread — `NSCache` is thread-safe.
    nonisolated func cachedImage(for url: URL, targetSize: CGSize) -> UIImage? {
        cache.object(forKey: Key(url: url, maxPixel: Self.maxPixel(for: targetSize)).cacheKey)
    }

    /// Returns a downsampled image for `url` sized for a `targetSize`-point frame.
    /// Throws on network/decoding failure (callers fall back to a placeholder).
    func image(for url: URL, targetSize: CGSize) async throws -> UIImage {
        let maxPixel = Self.maxPixel(for: targetSize)
        let key = Key(url: url, maxPixel: maxPixel)

        if let cached = cache.object(forKey: key.cacheKey) {
            return cached
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<UIImage, Error> { [session] in
            let (data, _) = try await session.data(from: url)
            try Task.checkCancellation()
            guard let image = Self.downsample(data: data, maxPixel: maxPixel) else {
                throw ImageLoaderError.decodingFailed
            }
            return image
        }
        inFlight[key] = task

        do {
            let image = try await task.value
            inFlight[key] = nil
            cache.setObject(image, forKey: key.cacheKey, cost: image.estimatedByteCost)
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// Warms the cache for an upcoming image (e.g. the next hero backdrop) without blocking a view.
    func prefetch(url: URL, targetSize: CGSize) {
        Task { try? await image(for: url, targetSize: targetSize) }
    }

    // MARK: - Downsampling

    private static func maxPixel(for targetSize: CGSize) -> Int {
        let longestSide = max(targetSize.width, targetSize.height) * renderScale
        // Round up to a step so near-identical sizes share a cache entry.
        return max(1, Int((longestSide / 32).rounded(.up)) * 32)
    }

    /// Decodes `data` straight to a thumbnail of `maxPixel` on its longest side. `ImageIO` does the
    /// decode here, off the main thread, so SwiftUI never decodes a full-resolution image at draw time.
    private static func downsample(data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}

enum ImageLoaderError: Error {
    case decodingFailed
}

private extension UIImage {
    /// Approximate decoded size in bytes, used as the NSCache cost.
    var estimatedByteCost: Int {
        guard let cg = cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}
