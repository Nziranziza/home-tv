import Foundation
import Testing
@testable import HomeTV

/// Enhance Dialogue and Reduce Loud Sounds: the FFmpeg filters, the AVPlayer tap's processing, the
/// menu's levels and the setting kept across titles.
@MainActor
struct AudioAdjustmentsTests {

    // MARK: - FFmpeg filters

    @Test func nothingOnMeansNoFilters() {
        #expect(AudioFilterGraph.filters(for: AudioAdjustments(), hasCentreChannel: true).isEmpty)
    }

    @Test func enhanceLiftsTheCentreChannelsSpeechBand() {
        let filters = AudioFilterGraph.filters(for: AudioAdjustments(dialogue: .enhance), hasCentreChannel: true)
        #expect(filters == ["volume=-5dB", "equalizer=f=2000:t=q:w=0.7:g=5:c=FC"])
    }

    @Test func stereoEnhanceMoreLiftsBothChannels() {
        let filters = AudioFilterGraph.filters(
            for: AudioAdjustments(dialogue: .enhanceMore), hasCentreChannel: false
        )
        #expect(filters == ["volume=-9dB", "equalizer=f=2000:t=q:w=0.7:g=9"])
    }

    @Test func reduceLoudSoundsAddsNoFilter() {
        // KSPlayer's FFmpeg has no compressor; the audio output compresses instead.
        let filters = AudioFilterGraph.filters(for: AudioAdjustments(reducesLoudSounds: true), hasCentreChannel: false)
        #expect(filters.isEmpty)
    }

    @Test func onlyFiltersKSPlayersFFmpegHasAreUsed() {
        for dialogue in AudioAdjustments.DialogueEnhancement.allCases {
            for centre in [false, true] {
                let filters = AudioFilterGraph.filters(
                    for: AudioAdjustments(dialogue: dialogue, reducesLoudSounds: true), hasCentreChannel: centre
                )
                let names = filters.compactMap { $0.split(separator: "=").first.map(String.init) }
                #expect(Set(names).isSubset(of: AudioFilterGraph.usedFilters))
            }
        }
    }

    // MARK: - AVPlayer tap processing

    private static let sampleRate = 48_000.0

    /// Runs `frames` of a sine through the processor and returns each channel's RMS over the last half.
    private static func rms(
        frequency: Double,
        amplitude: Float,
        channels: Int = 2,
        centre: Int? = nil,
        adjustments: AudioAdjustments,
        frames: Int = 48_000
    ) -> [Float] {
        var processor = AudioAdjustmentProcessor(sampleRate: sampleRate, channelCount: channels, centreChannel: centre)
        let buffers = (0..<channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: frames) }
        defer { buffers.forEach { $0.deallocate() } }
        for frame in 0..<frames {
            let sample = amplitude * Float(sin(2 * .pi * frequency * Double(frame) / sampleRate))
            buffers.forEach { $0[frame] = sample }
        }
        buffers.withUnsafeBufferPointer { pointers in
            // In blocks, as the tap is called.
            for start in stride(from: 0, to: frames, by: 512) {
                let block = pointers.map { $0 + start }
                block.withUnsafeBufferPointer {
                    processor.process($0, frameCount: min(512, frames - start), adjustments: adjustments)
                }
            }
        }
        return buffers.map { buffer in
            let tail = (frames / 2)..<frames
            let sum = tail.reduce(Float(0)) { $0 + buffer[$1] * buffer[$1] }
            return (sum / Float(tail.count)).squareRoot()
        }
    }

    private static func decibels(_ ratio: Float) -> Float { 20 * log10(ratio) }

    @Test func offLeavesTheSamplesUntouched() {
        let level = Self.rms(frequency: 2000, amplitude: 0.5, adjustments: AudioAdjustments())
        #expect(abs(level[0] - Float(0.5 / 2.0.squareRoot())) < 1e-4)
    }

    @Test func enhanceLiftsSpeechOverBass() {
        let input = Float(0.1 / 2.0.squareRoot())
        let adjustments = AudioAdjustments(dialogue: .enhance)
        let speech = Self.decibels(Self.rms(frequency: 2000, amplitude: 0.1, adjustments: adjustments)[0] / input)
        let bass = Self.decibels(Self.rms(frequency: 60, amplitude: 0.1, adjustments: adjustments)[0] / input)
        // Speech keeps its level; the rest drops 5 dB.
        #expect(abs(speech) < 0.5)
        #expect(abs(bass - -5) < 0.5)
    }

    @Test func enhanceMoreSetsSpeechFurtherApart() {
        func spread(_ dialogue: AudioAdjustments.DialogueEnhancement) -> Float {
            let adjustments = AudioAdjustments(dialogue: dialogue)
            let speech = Self.rms(frequency: 2000, amplitude: 0.1, adjustments: adjustments)[0]
            let bass = Self.rms(frequency: 60, amplitude: 0.1, adjustments: adjustments)[0]
            return Self.decibels(speech / bass)
        }
        #expect(spread(.enhanceMore) - spread(.enhance) > 3)
    }

    @Test func fullScaleSpeechDoesNotClip() {
        for dialogue in [AudioAdjustments.DialogueEnhancement.enhance, .enhanceMore] {
            let level = Self.rms(frequency: 2000, amplitude: 1, adjustments: AudioAdjustments(dialogue: dialogue))[0]
            // A full-scale sine's RMS.
            #expect(level <= Float(1 / 2.0.squareRoot()) * 1.01)
        }
    }

    @Test func onlyTheCentreIsLiftedInSurround() {
        let level = Self.rms(
            frequency: 2000, amplitude: 0.1, channels: 6, centre: 2, adjustments: AudioAdjustments(dialogue: .enhance)
        )
        #expect(Self.decibels(level[2] / level[0]) > 4.5)
    }

    @Test func reduceLoudSoundsBringsLoudAndQuietCloser() {
        let adjustments = AudioAdjustments(reducesLoudSounds: true)
        let loud = Self.rms(frequency: 200, amplitude: 0.9, adjustments: adjustments)[0]
        let quiet = Self.rms(frequency: 200, amplitude: 0.01, adjustments: adjustments)[0]
        // 39 dB apart going in.
        #expect(Self.decibels(loud / quiet) < 30)
        #expect(loud < Float(0.9 / 2.0.squareRoot()))
    }

    @Test func switchingGlidesInsteadOfJumping() {
        var processor = AudioAdjustmentProcessor(sampleRate: Self.sampleRate, channelCount: 1, centreChannel: nil)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0.5, count: 512)
        [buffer].withUnsafeBufferPointer {
            processor.process($0, frameCount: 512, adjustments: AudioAdjustments(reducesLoudSounds: true))
        }
        // A step to 0.5 can't move more than the 50 ms glide allows in one sample.
        let jumps = (1..<512).map { abs(buffer[$0] - buffer[$0 - 1]) }
        #expect(abs(buffer[0] - 0.5) < 0.01)
        #expect(jumps.max() ?? 0 < 0.01)
    }

    // MARK: - Menu and setting

    @Test func adjustmentsAreKeptAcrossTitles() throws {
        let defaults = try #require(UserDefaults(suiteName: "AudioAdjustmentsTests.\(UUID())"))
        let store = AudioAdjustmentsStore(defaults: defaults)
        let first = FakePlaybackEngine()
        PlayerAudio(engine: first, showID: "a", adjustmentsStore: store).setDialogue(.enhanceMore)
        let audio = PlayerAudio(engine: first, showID: "a", adjustmentsStore: store)
        audio.toggleReduceLoudSounds()

        let next = FakePlaybackEngine()
        _ = PlayerAudio(engine: next, showID: "b", adjustmentsStore: store)
        #expect(next.audioAdjustments == AudioAdjustments(dialogue: .enhanceMore, reducesLoudSounds: true))
    }

    @Test func menuBacksOutOfEnhanceDialogueBeforeClosing() throws {
        let (model, _) = try PlayerTransportTests.model()
        model.openAudioMenu()
        model.showAudioMenu(.enhanceDialogue)
        #expect(model.handleExit())
        #expect(model.audioMenu == .root)
        #expect(model.handleExit())
        #expect(model.audioMenu == nil)
    }
}
