/// The Language menu's tracks: the stream's own first, then add-on files, each with the device's
/// language first. An add-on file in a language the stream already has is left out.
enum SubtitleTrackList {
    static func tracks(
        embedded: [PlaybackTrack],
        external: [PlaybackTrack],
        deviceLanguage: String
    ) -> [PlaybackTrack] {
        let added = external.filter { file in
            !embedded.contains { SubtitleLanguage.sameWritten($0.languageCode, file.languageCode) }
        }
        return deviceFirst(embedded, deviceLanguage) + deviceFirst(groupedByLanguage(added), deviceLanguage)
    }

    private static func deviceFirst(_ tracks: [PlaybackTrack], _ deviceLanguage: String) -> [PlaybackTrack] {
        let device = tracks.filter { SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
        let others = tracks.filter { !SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
        return device + others
    }

    /// Files in the same language side by side, so `English (2)` follows `English`.
    private static func groupedByLanguage(_ tracks: [PlaybackTrack]) -> [PlaybackTrack] {
        var order: [String?] = []
        for track in tracks where !order.contains(track.languageCode) { order.append(track.languageCode) }
        return order.flatMap { language in tracks.filter { $0.languageCode == language } }
    }
}
