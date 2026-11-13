import Foundation

/// A quality badge on the Info tab, read from the playing stream.
enum PlayerBadge: Hashable, Sendable {
    case fourK
    case dolbyVision
    case hdr10
    case sdh
    case audioDescription

    var title: String {
        switch self {
        case .fourK: "4K"
        case .dolbyVision: "Dolby Vision"
        case .hdr10: "HDR10"
        case .sdh: "SDH"
        case .audioDescription: "AD"
        }
    }

    /// In the system player's order: resolution, dynamic range, then accessibility.
    static func badges(video: VideoFormat?, audio: [PlaybackTrack], subtitles: [PlaybackTrack]) -> [PlayerBadge] {
        var badges: [PlayerBadge] = []
        if let video {
            // Wide enough for a scope crop of UHD (3840×1600) too.
            if video.size.width >= 3200 || video.size.height >= 2000 { badges.append(.fourK) }
            switch video.dynamicRange {
            case .dolbyVision: badges.append(.dolbyVision)
            case .hdr10: badges.append(.hdr10)
            case .hlg, .sdr: break
            }
        }
        if subtitles.contains(where: \.isSDH) { badges.append(.sdh) }
        if audio.contains(where: \.isAudioDescription) { badges.append(.audioDescription) }
        return badges
    }
}
