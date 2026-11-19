import Foundation

/// The AVPlayer tap's audio processing: a speech-band lift with headroom, then a compressor, matching
/// `AudioFilterGraph`. Settings glide over 50 ms so switching never clicks. Real-time safe: no allocation
/// after init.
struct AudioAdjustmentProcessor {
    private struct Band {
        var z1: Float = 0
        var z2: Float = 0
    }

    private let channelCount: Int
    /// Channels whose speech band is lifted: the centre, else all.
    private let dialogueChannels: [Bool]
    private var bands: [Band]
    // Constant-peak band-pass, so `x + (g - 1) * band(x)` lifts the band by `g`.
    private let b0: Float
    private let a1: Float
    private let a2: Float
    private let glide: Float
    private let attack: Float
    private let release: Float

    private var lift: Float = 0
    private var headroom: Float = 1
    private var compression: Float = 0
    private var envelope: Float = 0

    init(sampleRate: Double, channelCount: Int, centreChannel: Int?) {
        self.channelCount = channelCount
        dialogueChannels = (0..<channelCount).map { centreChannel == nil || $0 == centreChannel }
        bands = Array(repeating: Band(), count: channelCount)
        let w0 = 2 * Double.pi * AudioAdjustmentTuning.speechFrequency / sampleRate
        let alpha = sin(w0) / (2 * AudioAdjustmentTuning.speechQ)
        let a0 = 1 + alpha
        b0 = Float(alpha / a0)
        a1 = Float(-2 * cos(w0) / a0)
        a2 = Float((1 - alpha) / a0)
        glide = Float(1 - exp(-1 / (0.05 * sampleRate)))
        attack = Float(exp(-1 / (AudioAdjustmentTuning.compressorAttack * sampleRate)))
        release = Float(exp(-1 / (AudioAdjustmentTuning.compressorRelease * sampleRate)))
    }

    /// Processes non-interleaved float samples in place, one pointer per channel.
    mutating func process(_ channels: UnsafeBufferPointer<UnsafeMutablePointer<Float>>, frameCount: Int,
                          adjustments: AudioAdjustments) {
        guard channels.count == channelCount else { return }
        let dialogue = AudioAdjustmentTuning.dialogue(adjustments.dialogue)
        let targetLift = Float(Self.gain(dialogue.boost) - 1)
        let targetHeadroom = Float(Self.gain(dialogue.headroom))
        let targetCompression: Float = adjustments.reducesLoudSounds ? 1 : 0
        if !adjustments.isActive, lift < 1e-4, abs(headroom - 1) < 1e-4, compression < 1e-4 {
            // Settled at off: untouched. The filters restart from silence, under a gliding lift.
            lift = 0
            headroom = 1
            compression = 0
            return
        }
        let threshold = Float(AudioAdjustmentTuning.compressorThreshold)
        let slope = Float(1 - 1 / AudioAdjustmentTuning.compressorRatio)
        let makeup = Float(AudioAdjustmentTuning.compressorMakeup)
        for frame in 0..<frameCount {
            lift += (targetLift - lift) * glide
            headroom += (targetHeadroom - headroom) * glide
            compression += (targetCompression - compression) * glide
            var peak: Float = 0
            for channel in 0..<channelCount {
                let x = channels[channel][frame]
                var band = bands[channel]
                let y = b0 * x + band.z1
                band.z1 = -a1 * y + band.z2
                band.z2 = -b0 * x - a2 * y
                bands[channel] = band
                let lifted = (x + (dialogueChannels[channel] ? lift * y : 0)) * headroom
                channels[channel][frame] = lifted
                peak = max(peak, abs(lifted))
            }
            guard compression > 1e-4 else { continue }
            envelope = peak > envelope
                ? attack * envelope + (1 - attack) * peak
                : release * envelope + (1 - release) * peak
            let level = 20 * log10(max(envelope, 1e-6))
            let reduction = max(level - threshold, 0) * slope
            let gain = 1 + compression * (pow(10, (makeup - reduction) / 20) - 1)
            for channel in 0..<channelCount {
                channels[channel][frame] *= gain
            }
        }
    }

    private static func gain(_ decibels: Double) -> Double { pow(10, decibels / 20) }
}
