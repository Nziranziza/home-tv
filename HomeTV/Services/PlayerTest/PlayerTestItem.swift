import Foundation

/// One sample file. Only `title`, `url` and `container` are always present.
struct PlayerTestItem: Codable, Hashable, Sendable {
    let title: String
    let url: URL
    let container: String
    var size: Int64?
    var video: String?
    var audio: String?
    var resolution: String?
    var hdr: String?
    var bitrate: Int?
    var headers: [String: String]?
    var note: String?
    var expect: PlayerTestExpectation?

    /// `MP4 · HEVC · 2160p · Dolby Vision · 1.2 GB`, from whichever fields are present.
    var detailLine: String {
        var parts = [container.uppercased()]
        if let video { parts.append(PlayerTestVocabulary.codecName(video)) }
        if let audio { parts.append(PlayerTestVocabulary.codecName(audio)) }
        if let resolution { parts.append(resolution) }
        if let hdr { parts.append(PlayerTestVocabulary.hdrName(hdr)) }
        if let bitrateText { parts.append(bitrateText) }
        if let sizeText { parts.append(sizeText) }
        return parts.joined(separator: " · ")
    }

    var bitrateText: String? {
        guard let bitrate else { return nil }
        let mbps = Double(bitrate) / 1_000_000
        return "\(mbps.formatted(.number.precision(.fractionLength(0...1)))) Mbps"
    }

    var sizeText: String? { size?.formatted(.byteCount(style: .file)) }

    /// The original file name, extension included, so Infuse treats it as a plain file.
    var filename: String { url.lastPathComponent }

    /// Why Infuse can't open this item, or nil when it can.
    var infuseBlockReason: String? {
        if url.isFileURL { return "Infuse can't open files stored inside HomeTV." }
        if let headers, !headers.isEmpty {
            return note ?? "Infuse's URL scheme can't send the headers this file needs."
        }
        return nil
    }
}
