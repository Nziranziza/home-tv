import Foundation

/// The FFmpeg audio filters for Enhance Dialogue, as `KSOptions.audioFilters` takes them. KSPlayer's FFmpeg
/// has only `volume`, `equalizer`, `atempo`, `aformat`, `anull` and `aresample`; an unknown filter crashes
/// its decoder. Reduce Loud Sounds is the audio output's dynamics processor instead (`KSPlaybackEngine`).
enum AudioFilterGraph {
    /// Filters KSPlayer's FFmpeg build includes that these use.
    static let usedFilters: Set<String> = ["volume", "equalizer"]

    /// Empty when Enhance Dialogue is off. With a centre channel only the centre's speech band is lifted.
    static func filters(for adjustments: AudioAdjustments, hasCentreChannel: Bool) -> [String] {
        var filters: [String] = []
        let dialogue = AudioAdjustmentTuning.dialogue(adjustments.dialogue)
        if adjustments.dialogue != .off {
            let channel = hasCentreChannel ? ":c=FC" : ""
            filters.append("volume=\(decibels(dialogue.headroom))")
            filters.append(
                "equalizer=f=\(number(AudioAdjustmentTuning.speechFrequency)):t=q"
                    + ":w=\(number(AudioAdjustmentTuning.speechQ)):g=\(number(dialogue.boost))\(channel)"
            )
        }
        return filters
    }

    private static func decibels(_ value: Double) -> String { "\(number(value))dB" }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
