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
        let track = remembered.flatMap { rememberedTrack(in: regular, $0) }
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

    /// The remembered track's match; one with no language is found by its title.
    private static func rememberedTrack(in tracks: [PlaybackTrack], _ choice: SubtitleChoice) -> PlaybackTrack? {
        guard SubtitleLanguage.base(choice.languageCode) != nil else {
            let matches = tracks.filter { SubtitleLanguage.base($0.languageCode) == nil && $0.name == choice.name }
            return matches.first { $0.isExternal == choice.isExternal } ?? matches.first
        }
        return bestMatch(
            in: tracks, language: choice.languageCode, isSDH: choice.isSDH, name: choice.name, isExternal: choice.isExternal
        )
    }

    /// A track in `language`: the same script or region first, then the same title, then the same
    /// source, stream or add-on, then the asked-for SDH, else plain subtitles before SDH. Ties go to the
    /// earlier track, the stream's own.
    private static func bestMatch(
        in tracks: [PlaybackTrack],
        language: String?,
        isSDH: Bool?,
        name: String? = nil,
        isExternal: Bool? = nil
    ) -> PlaybackTrack? {
        let wanted = Wanted(language: language, isSDH: isSDH, name: name, isExternal: isExternal)
        let candidates = tracks.filter { SubtitleLanguage.matches($0.languageCode, language) }
        return candidates.max { score($0, wanted) < score($1, wanted) }
    }

    private struct Wanted {
        let language: String?
        let isSDH: Bool?
        let name: String?
        let isExternal: Bool?
    }

    private static func score(_ track: PlaybackTrack, _ wanted: Wanted) -> Int {
        var score = 0
        if track.languageCode?.lowercased() == wanted.language?.lowercased() { score += 32 }
        let trackForm = SubtitleLanguage.scriptAndRegion(track.languageCode)
        let wantedForm = SubtitleLanguage.scriptAndRegion(wanted.language)
        if let script = trackForm.script, script == wantedForm.script { score += 16 }
        if let region = trackForm.region, region == wantedForm.region { score += 8 }
        if let name = wanted.name, !name.isEmpty, track.name == name { score += 4 }
        if let isExternal = wanted.isExternal, track.isExternal == isExternal { score += 2 }
        if track.isSDH == (wanted.isSDH ?? false) { score += 1 }
        return score
    }
}
