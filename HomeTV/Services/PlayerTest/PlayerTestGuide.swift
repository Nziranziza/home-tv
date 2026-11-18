import Foundation

/// What to look for when playing an entry, from its expectation, fields and where it sits.
enum PlayerTestGuide {
    static func checks(for entry: PlayerTestEntry) -> [String] {
        let item = entry.item
        var checks = [entry.expect.explanation]

        switch item.hdr {
        case "dolbyVision": checks.append(dolbyVision)
        case "hdr10": checks.append("The TV switches to HDR10.")
        case "hdr10plus": checks.append("The TV switches to HDR10+, or HDR10 if it lacks HDR10+.")
        case "hlg": checks.append("The TV switches to HLG.")
        case "sdr": checks.append("The TV stays in SDR, with normal colours.")
        default: if entry.matches("dolby vision") { checks.append(dolbyVision) }
        }

        if entry.matches("8k") {
            checks.append("8K is above Apple TV's output: a downscale, stutter or a clean failure.")
        } else if entry.matches("4k") {
            checks.append("Plays at 4K without dropped frames.")
        }
        if let bitrate = item.bitrate, bitrate >= 80_000_000, let text = item.bitrateText {
            checks.append("At \(text), watch for buffering and dropped frames.")
        }
        if item.video == "av1" {
            checks.append("AV1 is often decoded in software: watch for stutter at high resolutions.")
        }

        switch entry.sectionID {
        case "subtitles":
            checks.append("Turn on the subtitle track: it renders with its styling and stays in sync.")
        case "audio":
            checks.append("Sound plays from the right speakers, in sync with the picture.")
        case "3d":
            checks.append("tvOS can't output 3D: the 2D view or a clean failure both pass.")
        case "broken":
            checks.append("From a bug report: the player recovers, or shows an error, without freezing.")
        default:
            break
        }
        if entry.matches("atmos") {
            checks.append("The receiver or TV shows Atmos, or the audio downmixes cleanly.")
        }
        if entry.matches("hls") || entry.matches("m3u8") {
            checks.append("Adaptive stream: starts and switches quality without stalling.")
        }
        if entry.matches("encrypted") || entry.matches("cenc") {
            checks.append("DRM-protected: HomeTV can't decrypt it, so an error is the pass.")
        }
        if let headers = item.headers, !headers.isEmpty {
            let names = headers.keys.sorted().formatted(.list(type: .and))
            checks.append("Needs the \(names) header: HomeTV sends it, Infuse can't.")
        }
        return checks
    }

    private static let dolbyVision =
        "The TV switches to Dolby Vision. A purple or green picture means the Dolby Vision layer was ignored."
}
