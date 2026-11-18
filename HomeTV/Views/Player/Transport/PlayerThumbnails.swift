import CoreGraphics
import Foundation
import Observation

/// The scrub preview's image. Follows the scrub position on a coarse grid, one decode at a time, so a fast
/// scan only ever asks for where it is now.
@Observable
@MainActor
final class PlayerThumbnails {
    /// The system player snaps its preview to steps this far apart.
    static let gridStep: TimeInterval = 15
    /// About twice the preview's width in points, for a sharp 4K picture.
    static let pixelWidth = 800
    private static let cacheLimit = 40
    /// A frame that failed is asked for again after this, in case the read failure passed.
    static let retryDelay: Duration = .seconds(5)

    /// The latest decoded frame; kept while the next decodes so the preview doesn't blank.
    private(set) var image: CGImage?
    @ObservationIgnored private let makeThumbnailer: @MainActor () -> any PlaybackThumbnailer
    @ObservationIgnored private var thumbnailer: (any PlaybackThumbnailer)?
    @ObservationIgnored private var cache: [Int: CGImage] = [:]
    @ObservationIgnored private var cacheOrder: [Int] = []
    /// When each failed frame may be retried.
    @ObservationIgnored private var failed: [Int: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var followTask: Task<Void, Never>?

    init(makeThumbnailer: @escaping @MainActor () -> any PlaybackThumbnailer) {
        self.makeThumbnailer = makeThumbnailer
    }

    static func gridIndex(for time: TimeInterval) -> Int {
        Int((max(0, time) / gridStep).rounded(.down))
    }

    /// Keeps the image on `position` until `stop`.
    func follow(_ position: @escaping @MainActor () -> TimeInterval) {
        guard followTask == nil else { return }
        let thumbnailer = thumbnailer ?? makeThumbnailer()
        self.thumbnailer = thumbnailer
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let index = Self.gridIndex(for: position())
                if let cached = cache[index] {
                    if image !== cached { image = cached }
                } else if failed[index].map({ ContinuousClock.now >= $0 }) ?? true {
                    let frame = await thumbnailer.frame(
                        at: TimeInterval(index) * Self.gridStep,
                        maxPixelWidth: Self.pixelWidth
                    )
                    guard !Task.isCancelled else { return }
                    store(frame, at: index)
                    continue
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// The scrub ended: the next one starts from a blank frame.
    func stop() {
        followTask?.cancel()
        followTask = nil
        image = nil
    }

    func close() {
        stop()
        thumbnailer?.close()
        thumbnailer = nil
    }

    private func store(_ frame: CGImage?, at index: Int) {
        guard let frame else {
            failed[index] = .now + Self.retryDelay
            return
        }
        failed[index] = nil
        image = frame
        cache[index] = frame
        cacheOrder.append(index)
        if cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
