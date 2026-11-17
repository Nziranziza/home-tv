import AVFoundation

/// The simulator's thumbnailer: whatever AVFoundation can open, snapped to the keyframe before the time.
final class AVThumbnailer: PlaybackThumbnailer {
    private let generator: AVAssetImageGenerator

    init(url: URL, headers: [String: String]) {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .zero
    }

    func frame(at time: TimeInterval, maxPixelWidth: Int) async -> CGImage? {
        generator.maximumSize = CGSize(width: maxPixelWidth, height: 0)
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    func close() {
        generator.cancelAllCGImageGeneration()
    }
}

// AVAssetImageGenerator is documented as safe to call from any thread.
extension AVThumbnailer: @unchecked Sendable {}
