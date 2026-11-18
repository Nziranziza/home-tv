import Foundation

/// The Language menu's tracks: the stream's own first, then add-on files by language name, each with the
/// device's language first. Add-on files are listed even in a language the stream has, as a fallback for a
/// badly timed track.
enum SubtitleTrackList {
    static func tracks(
        embedded: [PlaybackTrack],
        external: [PlaybackTrack],
        deviceLanguage: String,
        locale: Locale = .current
    ) -> [PlaybackTrack] {
        deviceFirst(embedded, deviceLanguage) + deviceFirst(alphabetical(external, locale), deviceLanguage)
    }

    private static func deviceFirst(_ tracks: [PlaybackTrack], _ deviceLanguage: String) -> [PlaybackTrack] {
        let device = tracks.filter { SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
        let others = tracks.filter { !SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
        return device + others
    }

    /// Files grouped by language, the languages in alphabetical order of their names and each keeping its
    /// files' order, so `English (2)` follows `English`.
    private static func alphabetical(_ tracks: [PlaybackTrack], _ locale: Locale) -> [PlaybackTrack] {
        var order: [String?] = []
        for track in tracks where !order.contains(track.languageCode) { order.append(track.languageCode) }
        let names = Dictionary(uniqueKeysWithValues: order.map { code in
            (code ?? "", tracks.first { $0.languageCode == code }.map { SubtitleTrackName.name(for: $0, locale: locale) } ?? "")
        })
        return order
            .sorted { names[$0 ?? "", default: ""].localizedStandardCompare(names[$1 ?? "", default: ""]) == .orderedAscending }
            .flatMap { language in tracks.filter { $0.languageCode == language } }
    }
}
