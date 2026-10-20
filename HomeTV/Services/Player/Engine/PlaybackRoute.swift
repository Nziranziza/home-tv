import Foundation

/// Which decoder a stream starts on. Native keeps AVPlayer's Dolby Vision and Atmos; containers
/// AVPlayer can't open go straight to FFmpeg instead of failing there first.
enum PlaybackRoute: Equatable, Sendable {
    case native
    case ffmpeg

    private static let ffmpegExtensions: Set<String> = ["mkv", "avi", "webm"]

    static func forURL(_ url: URL) -> PlaybackRoute {
        ffmpegExtensions.contains(url.pathExtension.lowercased()) ? .ffmpeg : .native
    }
}
