/// The audio adjustments' settings, shared by the FFmpeg filters and the AVPlayer tap so both routes sound alike.
enum AudioAdjustmentTuning {
    /// The speech band's centre and width.
    static let speechFrequency: Double = 2000
    static let speechQ: Double = 0.7

    /// The speech-band boost, and the cut to every channel that keeps the boost from clipping.
    static func dialogue(_ enhancement: AudioAdjustments.DialogueEnhancement) -> (boost: Double, headroom: Double) {
        switch enhancement {
        case .off: (0, 0)
        case .enhance: (5, -2)
        case .enhanceMore: (9, -4)
        }
    }

    static let compressorThreshold: Double = -24
    static let compressorRatio: Double = 4
    static let compressorAttack: Double = 0.010
    static let compressorRelease: Double = 0.250
    /// Lifts quiet passages once the peaks are down.
    static let compressorMakeup: Double = 6
    /// Apple's Dynamics Processor takes headroom over the threshold, not a ratio: 6 dB is about 4:1 at full scale.
    static let dynamicsHeadroom: Double = 6

    /// Codecs AVPlayer passes through to the TV or receiver undecoded, so a tap never sees their samples.
    static let passthroughCodecs: Set<String> = ["ac3", "eac3"]
}
