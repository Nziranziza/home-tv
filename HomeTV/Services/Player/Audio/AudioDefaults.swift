/// Which audio track a title opens with: a choice remembered for the show, else the original language,
/// else the device's language. Audio description only when it was the remembered choice.
enum AudioDefaults {
    static func track(
        in tracks: [PlaybackTrack],
        deviceLanguage: String,
        remembered: AudioChoice?
    ) -> PlaybackTrack? {
        if let remembered, let match = rememberedTrack(in: tracks, remembered) { return match }
        let main = tracks.filter { !$0.isAudioDescription }
        let pool = main.isEmpty ? tracks : main
        if let original = originalLanguage(in: tracks) {
            let candidates = pool.filter { SubtitleLanguage.matches($0.languageCode, original) }
            if let pick = candidates.first(where: \.isOriginal)
                ?? candidates.first(where: \.isDefault)
                ?? candidates.first {
                return pick
            }
        }
        return pool.first { SubtitleLanguage.matches($0.languageCode, deviceLanguage) }
            ?? pool.first(where: \.isDefault)
            ?? pool.first
    }

    /// The title's original language: the track flagged original, else the default track unless it's a
    /// dub. nil when the stream doesn't say.
    static func originalLanguage(in tracks: [PlaybackTrack]) -> String? {
        let original = tracks.first(where: \.isOriginal)
            ?? tracks.first { $0.isDefault && !$0.isDub && !$0.isAudioDescription }
        guard let code = original?.languageCode, SubtitleLanguage.base(code) != nil else { return nil }
        return code
    }

    /// A track in the remembered language and kind, closest by title, codec and channels.
    private static func rememberedTrack(in tracks: [PlaybackTrack], _ choice: AudioChoice) -> PlaybackTrack? {
        let language = SubtitleLanguage.base(choice.languageCode)
        let candidates = tracks.filter { track in
            guard track.isAudioDescription == choice.isAudioDescription else { return false }
            guard language != nil else {
                return SubtitleLanguage.base(track.languageCode) == nil && track.name == choice.name
            }
            return SubtitleLanguage.matches(track.languageCode, choice.languageCode)
        }
        return candidates.max { score($0, choice) < score($1, choice) }
    }

    private static func score(_ track: PlaybackTrack, _ choice: AudioChoice) -> Int {
        var score = 0
        if let name = choice.name, !name.isEmpty, track.name == name { score += 4 }
        if let codec = choice.codec, track.codec == codec { score += 2 }
        if let channels = choice.channelCount, track.channelCount == channels { score += 1 }
        return score
    }
}
