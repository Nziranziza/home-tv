/// An audio track's codec and channels as the menu shows them: `TrueHD 7.1`, `AC-3 5.1`.
enum AudioFormatName {
    private static let codecs: [String: String] = [
        "truehd": "TrueHD", "ac3": "AC-3", "eac3": "E-AC-3", "dts": "DTS", "aac": "AAC", "flac": "FLAC",
        "alac": "ALAC", "opus": "Opus", "vorbis": "Vorbis", "mp3": "MP3", "mp2": "MP2",
    ]

    /// nil when the track reports neither.
    static func label(for track: PlaybackTrack) -> String? {
        let parts = [codec(track.codec, profile: track.codecProfile), channels(track.channelCount)]
        let label = parts.compactMap(\.self).joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    static func codec(_ codec: String?, profile: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        // FFmpeg names DTS's variants by profile: `DTS-HD MA`, `DTS:X`.
        if codec == "dts", let profile, profile.hasPrefix("DTS") { return profile }
        if codec.hasPrefix("pcm") { return "PCM" }
        return codecs[codec] ?? codec.uppercased()
    }

    static func channels(_ count: Int?) -> String? {
        switch count {
        case nil, 0?: nil
        case 1?: "Mono"
        case 2?: "Stereo"
        case 3?: "2.1"
        case 6?: "5.1"
        case 7?: "6.1"
        case 8?: "7.1"
        case let count?: "\(count)ch"
        }
    }
}
