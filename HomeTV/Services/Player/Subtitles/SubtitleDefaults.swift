/// Which subtitles a title opens with. Off, unless the audio isn't in the device's language, in which case
/// on in the device's language. A choice remembered for the show wins over both. Forced subtitles show
/// whenever subtitles are off.
enum SubtitleDefaults {
    struct Selection: Equatable {
        var isOn: Bool
        /// The track On shows, and the Language row names.
        var track: PlaybackTrack?
        /// Shown while subtitles are off.
        var forcedTrack: PlaybackTrack?

        /// What the engine should show.
        var shown: PlaybackTrack? { isOn ? track : forcedTrack }
    }

    static func selection(
        for tracks: [PlaybackTrack],
        audioLanguage: String?,
        deviceLanguage: String,
        remembered: SubtitleChoice?
    ) -> Selection {
        let regular = tracks.filter { !$0.isForced }
        let deviceTrack = bestMatch(in: regular, language: deviceLanguage, isSDH: nil)
        let track = remembered.flatMap { bestMatch(in: regular, language: $0.languageCode, isSDH: $0.isSDH) }
            ?? deviceTrack
            ?? regular.first
        let isOn: Bool
        if let remembered {
            isOn = remembered.isOn && track != nil
        } else {
            let audio = SubtitleLanguage.base(audioLanguage)
            isOn = audio != nil && audio != SubtitleLanguage.base(deviceLanguage) && deviceTrack != nil
        }
        return Selection(isOn: isOn, track: track, forcedTrack: forcedTrack(in: tracks, audioLanguage, deviceLanguage))
    }

    /// The forced track for the audio's language, else the device's, else one with no language.
    private static func forcedTrack(
        in tracks: [PlaybackTrack],
        _ audioLanguage: String?,
        _ deviceLanguage: String
    ) -> PlaybackTrack? {
        let forced = tracks.filter(\.isForced)
        return forced.first { SubtitleLanguage.matches($0.languageCode, audioLanguage) }
            ?? forced.first { SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
            ?? forced.first { SubtitleLanguage.base($0.languageCode) == nil }
    }

    /// A track in `language`: the same script or region first, then the asked-for SDH, else plain
    /// subtitles before SDH.
    private static func bestMatch(in tracks: [PlaybackTrack], language: String?, isSDH: Bool?) -> PlaybackTrack? {
        let candidates = tracks.filter { SubtitleLanguage.matches($0.languageCode, language) }
        return candidates.max { score($0, language, isSDH) < score($1, language, isSDH) }
    }

    private static func score(_ track: PlaybackTrack, _ language: String?, _ isSDH: Bool?) -> Int {
        var score = 0
        if track.languageCode?.lowercased() == language?.lowercased() { score += 2 }
        if track.isSDH == (isSDH ?? false) { score += 1 }
        return score
    }
}
