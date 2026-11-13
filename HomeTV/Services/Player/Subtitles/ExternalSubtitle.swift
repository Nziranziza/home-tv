import Foundation

/// A subtitle file an add-on attached to the stream, usually SRT. Fetched only once it's selected.
struct ExternalSubtitle: Hashable, Sendable {
    let url: URL
    /// Normalized: `en` for `eng`, `pt-BR` for OpenSubtitles' `pob`.
    let languageCode: String?

    /// The stream's add-on subtitles, without repeats of the same file. The add-on's own id and name are
    /// dropped; rows only ever show the language.
    static func list(from subtitles: [StreamSubtitle]?) -> [ExternalSubtitle] {
        var seen: Set<URL> = []
        return (subtitles ?? []).compactMap { subtitle in
            guard let raw = subtitle.url, let url = URL(string: raw),
                  url.scheme == "http" || url.scheme == "https",
                  seen.insert(url).inserted else { return nil }
            return ExternalSubtitle(url: url, languageCode: SubtitleLanguage.normalized(subtitle.lang))
        }
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
