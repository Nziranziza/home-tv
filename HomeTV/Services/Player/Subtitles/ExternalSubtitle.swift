import Foundation

/// A subtitle file from an add-on, attached to the stream or from a subtitle add-on, usually SRT. Fetched only once it's selected.
struct ExternalSubtitle: Hashable, Sendable {
    let url: URL
    /// Normalized: `en` for `eng`, `pt-BR` for OpenSubtitles' `pob`.
    let languageCode: String?
    /// What the file was made for, as the add-on named it, e.g. `Movie.2019.1080p.BluRay.x264-GROUP`.
    var releaseName: String?
    var releaseGroup: String?
    /// The release's source, e.g. `BluRay` or `WEB`.
    var releaseFormat: String?
    /// Frames per second the file was timed for.
    var frameRate: Double?

    /// The add-on's files, in its order, without repeats. The add-on's own id and name are dropped; rows
    /// only ever show the language and the release.
    static func list(from subtitles: [StreamSubtitle]?) -> [ExternalSubtitle] {
        let files = (subtitles ?? []).compactMap { subtitle -> ExternalSubtitle? in
            guard let raw = subtitle.url, let url = URL(string: raw),
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            return ExternalSubtitle(
                url: url,
                languageCode: SubtitleLanguage.normalized(subtitle.lang),
                releaseName: releaseName(subtitle),
                releaseGroup: subtitle.releaseGroup.flatMap { $0.isEmpty ? nil : $0 },
                releaseFormat: subtitle.releaseFormat.flatMap { $0.isEmpty ? nil : $0 },
                frameRate: subtitle.fpsMilli.flatMap { $0 > 0 ? Double($0) / 1000 : nil }
            )
        }
        return merged([], adding: files)
    }

    /// `files` after `existing`, skipping a file already listed. `existing` keeps its order, so its track
    /// ids don't move.
    static func merged(_ existing: [ExternalSubtitle], adding files: [ExternalSubtitle]) -> [ExternalSubtitle] {
        var urls = Set(existing.map(\.url))
        return existing + files.filter { urls.insert($0.url).inserted }
    }

    private static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "sub", "vtt", "txt", "smi"]

    /// The subtitle's file name without its extension, else the release it names.
    private static func releaseName(_ subtitle: StreamSubtitle) -> String? {
        if var name = subtitle.subtitleFileName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            if let dot = name.lastIndex(of: "."), subtitleExtensions.contains(name[name.index(after: dot)...].lowercased()) {
                name = String(name[..<dot]).trimmingCharacters(in: .whitespaces)
            }
            if !name.isEmpty { return name }
        }
        let release = subtitle.movieReleaseName?.trimmingCharacters(in: .whitespaces)
        return release?.isEmpty == false ? release : nil
    }

    /// Tracks the engine lists for add-on files: negative ids, clear of the stream's own.
    func track(at index: Int, isSelected: Bool) -> PlaybackTrack {
        PlaybackTrack(
            id: Self.trackID(at: index),
            kind: .subtitle,
            name: "",
            languageCode: languageCode,
            isSelected: isSelected,
            isExternal: true
        )
    }

    static func trackID(at index: Int) -> Int32 { -1 - Int32(index) }

    /// The add-on file a track stands for.
    static func index(of track: PlaybackTrack) -> Int? {
        track.isExternal ? Int(-1 - track.id) : nil
    }
}
