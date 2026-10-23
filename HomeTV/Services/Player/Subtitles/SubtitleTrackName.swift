import Foundation

/// A subtitle track's name in the menu: its language in the viewer's words, then `SDH` for subtitles for
/// the deaf and hard of hearing, like `English SDH` or `Chinese, Simplified SDH`.
enum SubtitleTrackName {
    static func name(for track: PlaybackTrack, locale: Locale = .current) -> String {
        let language = SubtitleLanguage.base(track.languageCode) == nil
            ? nil
            : track.languageCode.flatMap { locale.localizedString(forIdentifier: $0) }
        let base = language ?? (track.name.isEmpty ? unknownName(locale) : track.name)
        return track.isSDH ? "\(base) SDH" : base
    }

    /// Names in list order. A name shared by several tracks is followed by the track's own title, where
    /// that tells them apart.
    static func names(for tracks: [PlaybackTrack], locale: Locale = .current) -> [String] {
        let names = tracks.map { name(for: $0, locale: locale) }
        return zip(tracks, names).map { track, name in
            let isShared = names.count { $0 == name } > 1
            guard isShared, !track.name.isEmpty, !name.localizedStandardContains(track.name) else { return name }
            return "\(name) (\(track.name))"
        }
    }

    private static func unknownName(_ locale: Locale) -> String {
        locale.localizedString(forIdentifier: "und") ?? "Unknown"
    }
}
