import Foundation

/// A ready-made test: the files that exercise one format, with what it checks.
struct PlayerTestPreset: Identifiable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case video, audio, subtitles, robustness

        var id: String { rawValue }

        var title: String {
            switch self {
            case .video: "Video"
            case .audio: "Audio"
            case .subtitles: "Subtitles"
            case .robustness: "Streaming & Robustness"
            }
        }
    }

    let id: String
    let category: Category
    let title: String
    let symbol: String
    /// What this test checks, in a sentence.
    let summary: String
    /// Searches, any of which selects a file. Empty selects the whole `section`.
    var anyOf: [String] = []
    var section: String?

    func matches(_ entry: PlayerTestEntry) -> Bool {
        if let section, entry.sectionID != section { return false }
        return anyOf.isEmpty || anyOf.contains(where: entry.matches)
    }

    static let all: [PlayerTestPreset] = [
        .init(id: "dolby-vision", category: .video, title: "Dolby Vision", symbol: "sparkles.tv",
              summary: "The TV switches to Dolby Vision, with no purple or green tint.", anyOf: ["dolby vision"]),
        .init(id: "hdr10", category: .video, title: "HDR10", symbol: "sun.max",
              summary: "The TV switches to HDR and highlights aren't clipped.", anyOf: ["hdr10"]),
        .init(id: "hdr10plus-hlg", category: .video, title: "HDR10+ & HLG", symbol: "sun.horizon",
              summary: "Dynamic and broadcast HDR switch the TV into HDR.", anyOf: ["hdr10+", "hlg"]),
        .init(id: "4k", category: .video, title: "4K", symbol: "4k.tv",
              summary: "Full 4K plays without dropped frames.", anyOf: ["4k"]),
        .init(id: "8k", category: .video, title: "8K", symbol: "arrow.up.left.and.arrow.down.right",
              summary: "Above Apple TV's output: a downscale or a clean failure.", anyOf: ["8k"]),
        .init(id: "hevc", category: .video, title: "HEVC", symbol: "film",
              summary: "Hardware HEVC decode, 8- and 10-bit.", anyOf: ["hevc"]),
        .init(id: "av1", category: .video, title: "AV1", symbol: "film.stack",
              summary: "AV1 decodes smoothly, often in software.", anyOf: ["av1"]),
        .init(id: "vp9", category: .video, title: "VP9", symbol: "film",
              summary: "VP9 from WebM and Matroska.", anyOf: ["vp9"]),
        .init(id: "vvc", category: .video, title: "H.266 VVC", symbol: "film.circle",
              summary: "The newest codec: plays, or fails cleanly.", anyOf: ["vvc", "h266"]),
        .init(id: "10bit", category: .video, title: "10-bit", symbol: "paintpalette",
              summary: "Smooth gradients with no banding.", anyOf: ["10bit", "10 bit"]),
        .init(id: "bitrate", category: .video, title: "High Bitrate", symbol: "speedometer",
              summary: "3 to 400 Mbps: no buffering or dropped frames.", section: "bitrate"),

        .init(id: "atmos", category: .audio, title: "Dolby Atmos", symbol: "hifispeaker.2",
              summary: "Atmos reaches the receiver, or downmixes cleanly.", anyOf: ["atmos"]),
        .init(id: "truehd", category: .audio, title: "Dolby TrueHD", symbol: "hifispeaker",
              summary: "Lossless Dolby audio plays in sync.", anyOf: ["truehd"]),
        .init(id: "eac3", category: .audio, title: "Dolby Digital Plus", symbol: "speaker.wave.3",
              summary: "E-AC-3, the streaming-service surround format.", anyOf: ["eac3"]),
        .init(id: "ac3", category: .audio, title: "Dolby Digital", symbol: "speaker.wave.2",
              summary: "AC-3 surround from discs and broadcasts.", anyOf: ["ac3"]),
        .init(id: "dts", category: .audio, title: "DTS", symbol: "speaker.wave.3.fill",
              summary: "DTS and DTS-HD decode or pass through.", anyOf: ["dts"]),
        .init(id: "lossless", category: .audio, title: "Lossless", symbol: "waveform",
              summary: "FLAC and ALAC, including hi-res.", anyOf: ["lossless", "flac", "alac"]),
        .init(id: "multichannel", category: .audio, title: "Multichannel", symbol: "speaker.3",
              summary: "Each channel comes out of the right speaker.", anyOf: ["multichannel", "channel layouts"]),
        .init(id: "opus", category: .audio, title: "Opus", symbol: "waveform.path",
              summary: "Opus from WebM and Ogg.", anyOf: ["opus"]),

        .init(id: "subtitles", category: .subtitles, title: "All Subtitles", symbol: "captions.bubble",
              summary: "Every subtitle format renders and stays in sync.", section: "subtitles"),
        .init(id: "pgs", category: .subtitles, title: "PGS (Blu-ray)", symbol: "rectangle.and.text.magnifyingglass",
              summary: "Bitmap Blu-ray subtitles render sharply.", anyOf: ["pgs", "bluray"], section: "subtitles"),
        .init(id: "dvd-dvb", category: .subtitles, title: "DVD & DVB", symbol: "opticaldisc",
              summary: "VobSub and broadcast bitmap subtitles.", anyOf: ["vob", "dvb"], section: "subtitles"),
        .init(id: "captions", category: .subtitles, title: "Closed Captions", symbol: "captions.bubble.fill",
              summary: "CEA-608/708 captions embedded in the video.", anyOf: ["subcc", "608", "708"]),
        .init(id: "sami", category: .subtitles, title: "SAMI", symbol: "text.bubble",
              summary: "Microsoft SAMI text subtitles.", anyOf: ["sami"]),

        .init(id: "hls", category: .robustness, title: "HLS", symbol: "antenna.radiowaves.left.and.right",
              summary: "Adaptive streams start and switch quality.", anyOf: ["hls", "m3u8"]),
        .init(id: "encrypted", category: .robustness, title: "Encrypted", symbol: "lock",
              summary: "DRM files show an error instead of hanging.", anyOf: ["encrypted", "cenc"]),
        .init(id: "broken", category: .robustness, title: "Broken Files", symbol: "exclamationmark.triangle",
              summary: "Damaged files recover or fail cleanly.", section: "broken"),
        .init(id: "fail", category: .robustness, title: "Should Fail", symbol: "xmark.octagon",
              summary: "Not media: a prompt error message.", section: "fail"),
        .init(id: "3d", category: .robustness, title: "3D", symbol: "cube",
              summary: "tvOS can't output 3D: the 2D view or a clean failure.", section: "3d"),
    ]

    static func preset(id: String) -> PlayerTestPreset? { all.first { $0.id == id } }
}
