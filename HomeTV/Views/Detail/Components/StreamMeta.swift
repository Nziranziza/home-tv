import Foundation

/// Everything parsed out of a stream's title/name/description, computed ONCE at load time
/// so filtering, grouping, and rendering read plain stored fields (no regex per focus move).
struct StreamMeta: Hashable {
    let resolution: String
    let resolutionRank: Int
    let hdr: String?
    let codec: String?
    let bitDepth: String?
    let audio: String?
    let sourceTag: String?
    let sourceIsWarning: Bool
    let size: String?
    let releaseName: String

    static func make(from stream: Stream) -> StreamMeta {
        let haystack = "\(stream.title ?? "") \(stream.name ?? "") \(stream.description ?? "")"
        func matches(_ pattern: String) -> Bool {
            haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        let resolution: String
        if matches(#"\b(4K|2160p|UHD)\b"#) { resolution = "4K" }
        else if matches(#"\b1080p\b"#) { resolution = "1080p" }
        else if matches(#"\b720p\b"#) { resolution = "720p" }
        else if matches(#"\b480p\b"#) { resolution = "480p" }
        else if matches(#"\b(SD|CAM|TS)\b"#) { resolution = "SD" }
        else { resolution = "AUTO" }

        let hdr: String?
        if haystack.localizedCaseInsensitiveContains("DV") || haystack.localizedCaseInsensitiveContains("Dolby Vision") {
            hdr = "DV"
        } else if haystack.localizedCaseInsensitiveContains("HDR") {
            hdr = "HDR"
        } else {
            hdr = nil
        }

        let codec: String?
        if matches(#"\bav1\b"#) { codec = "AV1" }
        else if matches(#"\b(x265|h\.?265|hevc)\b"#) { codec = "HEVC" }
        else if matches(#"\b(x264|h\.?264|avc)\b"#) { codec = "H.264" }
        else { codec = nil }

        let bitDepth: String?
        if matches(#"\b10-?bit\b"#) { bitDepth = "10-bit" }
        else if matches(#"\b8-?bit\b"#) { bitDepth = "8-bit" }
        else { bitDepth = nil }

        // Audio format, strongest/most-specific first.
        let audio: String?
        if matches(#"\batmos\b"#) { audio = "Dolby Atmos" }
        else if matches(#"\b(truehd|true-hd)\b"#) { audio = "Dolby TrueHD" }
        else if matches(#"\bdts-?hd\b"#) { audio = "DTS-HD" }
        else if matches(#"\bdts\b"#) { audio = "DTS" }
        else if matches(#"\b(ddp|dd\+|e-?ac-?3|eac3)\b"#) { audio = "Dolby Digital+" }
        else if matches(#"\b(dd|ac-?3|ac3)\b"#) { audio = "Dolby Digital" }
        else if matches(#"\baac\b"#) { audio = "AAC" }
        else if matches(#"\bflac\b"#) { audio = "FLAC" }
        else { audio = nil }

        // CAM-type rips flagged as a warning so they're easy to avoid.
        let sourceTag: String?
        let sourceIsWarning: Bool
        if matches(#"\b(cam|camrip|hdcam|ts|telesync|hdts)\b"#) { sourceTag = "CAM"; sourceIsWarning = true }
        else if matches(#"\bremux\b"#) { sourceTag = "REMUX"; sourceIsWarning = false }
        else if matches(#"\b(blu-?ray|bdrip|brrip|bd)\b"#) { sourceTag = "BluRay"; sourceIsWarning = false }
        else if matches(#"\bweb-?dl\b"#) { sourceTag = "WEB-DL"; sourceIsWarning = false }
        else if matches(#"\b(webrip|web)\b"#) { sourceTag = "WEB"; sourceIsWarning = false }
        else { sourceTag = nil; sourceIsWarning = false }

        let size: String?
        let sizeHaystack = "\(stream.title ?? "") \(stream.description ?? "")"
        if let range = sizeHaystack.range(of: #"(\d+(?:\.\d+)?)\s?(GB|MB|TB)"#, options: [.regularExpression, .caseInsensitive]) {
            size = String(sizeHaystack[range])
        } else {
            size = nil
        }

        // Torrentio packs name + seeders + size across several lines (often with emoji);
        // keep just the first non-empty line as the title.
        let source = stream.title ?? stream.name ?? "Stream"
        let releaseName = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Stream"

        return StreamMeta(
            resolution: resolution,
            resolutionRank: StreamPickerView.qualityRank(resolution),
            hdr: hdr,
            codec: codec,
            bitDepth: bitDepth,
            audio: audio,
            sourceTag: sourceTag,
            sourceIsWarning: sourceIsWarning,
            size: size,
            releaseName: releaseName
        )
    }
}
