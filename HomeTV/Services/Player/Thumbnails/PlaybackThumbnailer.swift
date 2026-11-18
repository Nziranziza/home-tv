import CoreGraphics
import Foundation

/// Decodes preview frames from a stream on demand, for the scrub thumbnail. No trickplay files needed.
protocol PlaybackThumbnailer: Sendable {
    /// The keyframe at or just before `time`, at most `maxPixelWidth` wide; nil if it can't be decoded.
    func frame(at time: TimeInterval, maxPixelWidth: Int) async -> CGImage?
    /// Aborts any read in flight and stops decoding. The thumbnailer can't be reused.
    func close()
}

/// The thumbnailer for this build: FFmpeg on the Apple TV, AVFoundation in the simulator.
enum PlaybackThumbnailers {
    static func make(url: URL, headers: [String: String]) -> any PlaybackThumbnailer {
        #if canImport(KSPlayer)
        FFmpegThumbnailer(url: url, headers: headers)
        #else
        AVThumbnailer(url: url, headers: headers)
        #endif
    }
}
