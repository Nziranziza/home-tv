import Foundation

/// Audio tracks' names in the menu: `Original: English` for the original language, `AD` after audio
/// description. Tracks that would read the same get their codec and channels underneath.
enum AudioTrackName {
    static func title(for track: PlaybackTrack, originalLanguage: String?, locale: Locale = .current) -> String {
        let language = SubtitleLanguage.base(track.languageCode) == nil
            ? nil
            : track.languageCode.flatMap { locale.localizedString(forIdentifier: $0) }
        var title = language ?? (track.name.isEmpty ? unknownName(locale) : track.name)
        if language != nil, SubtitleLanguage.matches(track.languageCode, originalLanguage) {
            title = "Original: \(title)"
        }
        return track.isAudioDescription ? "\(title) AD" : title
    }

    static func options(for tracks: [PlaybackTrack], locale: Locale = .current) -> [AudioTrackOption] {
        let original = AudioDefaults.originalLanguage(in: tracks)
        let titles = tracks.map { title(for: $0, originalLanguage: original, locale: locale) }
        let formats = tracks.map(AudioFormatName.label)
        return tracks.indices.map { index in
            let title = titles[index]
            let siblings = titles.indices.filter { titles[$0] == title }
            guard siblings.count > 1 else { return AudioTrackOption(track: tracks[index], title: title, detail: nil) }
            // The format where it tells them apart, else the track's own title.
            let format = formats[index]
            let name = tracks[index].name
            let detail: String? = if let format, siblings.count(where: { formats[$0] == format }) == 1 {
                format
            } else if !name.isEmpty, !title.localizedStandardContains(name) {
                name
            } else {
                format
            }
            return AudioTrackOption(track: tracks[index], title: title, detail: detail)
        }
    }

    private static func unknownName(_ locale: Locale) -> String {
        locale.localizedString(forIdentifier: "und") ?? "Unknown"
    }
}
