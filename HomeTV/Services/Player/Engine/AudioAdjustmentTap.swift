import AVFoundation
import MediaToolbox
import Synchronization

/// Runs `AudioAdjustmentProcessor` inside an AVPlayer item through an audio tap. Taps every audio track
/// but the ones AVPlayer passes through undecoded (AC-3, E-AC-3 and Atmos); HLS can't be tapped at all.
@MainActor
final class AudioAdjustmentTap {
    /// Whether any of the item's audio can be adjusted.
    let isAvailable: Bool
    private let contexts: [AudioTapContext]

    private init(contexts: [AudioTapContext]) {
        self.contexts = contexts
        isAvailable = !contexts.isEmpty
    }

    static func install(on item: AVPlayerItem, adjustments: AudioAdjustments) async -> AudioAdjustmentTap {
        // HLS lists no tracks.
        let tracks = (try? await item.asset.loadTracks(withMediaType: .audio)) ?? []
        var parameters: [AVAudioMixInputParameters] = []
        var contexts: [AudioTapContext] = []
        for track in tracks {
            guard let description = try? await track.load(.formatDescriptions).first,
                  !isPassthrough(description) else { continue }
            let context = AudioTapContext(centreChannel: centreChannel(of: description))
            context.update(adjustments)
            guard let tap = context.makeTap() else { continue }
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTapProcessor = tap
            parameters.append(input)
            contexts.append(context)
        }
        if !parameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            item.audioMix = mix
        }
        PlaybackDiagnostics.log("audio tap on \(contexts.count) of \(tracks.count) tracks")
        return AudioAdjustmentTap(contexts: contexts)
    }

    func update(_ adjustments: AudioAdjustments) {
        contexts.forEach { $0.update(adjustments) }
    }

    private static func isPassthrough(_ description: CMFormatDescription) -> Bool {
        let codec = CMFormatDescriptionGetMediaSubType(description)
        return codec == kAudioFormatAC3 || codec == kAudioFormatEnhancedAC3
    }

    /// The centre's position in the decoded channels, when the track's layout names one.
    private static func centreChannel(of description: CMFormatDescription) -> Int? {
        var size = 0
        guard let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &size) else { return nil }
        let tag = layout.pointee.mChannelLayoutTag
        switch tag {
        case kAudioChannelLayoutTag_UseChannelDescriptions:
            return centre(in: layout)
        case kAudioChannelLayoutTag_UseChannelBitmap:
            let bitmap = layout.pointee.mChannelBitmap.rawValue
            let centre = AudioChannelBitmap.bit_Center.rawValue
            guard bitmap & centre != 0 else { return nil }
            return (bitmap & (centre - 1)).nonzeroBitCount
        default:
            var tag = tag
            var expandedSize: UInt32 = 0
            let tagSize = UInt32(MemoryLayout<AudioChannelLayoutTag>.size)
            guard AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag, tagSize, &tag, &expandedSize)
                == noErr, expandedSize > 0 else { return nil }
            let expanded = UnsafeMutableRawPointer.allocate(
                byteCount: Int(expandedSize), alignment: MemoryLayout<AudioChannelLayout>.alignment
            )
            defer { expanded.deallocate() }
            guard AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, tagSize, &tag, &expandedSize, expanded)
                == noErr else { return nil }
            return centre(in: expanded.assumingMemoryBound(to: AudioChannelLayout.self))
        }
    }

    private static func centre(in layout: UnsafePointer<AudioChannelLayout>) -> Int? {
        guard let offset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) else { return nil }
        let descriptions = (UnsafeRawPointer(layout) + offset).assumingMemoryBound(to: AudioChannelDescription.self)
        let count = Int(layout.pointee.mNumberChannelDescriptions)
        return (0..<count).first { descriptions[$0].mChannelLabel == kAudioChannelLabel_Center }
    }
}

/// One tapped track's state, shared between the main actor (settings) and the audio thread (samples).
private final class AudioTapContext: @unchecked Sendable {
    let centreChannel: Int?
    /// `AudioAdjustments` packed for the audio thread: the dialogue case's index, plus 4 for Reduce Loud Sounds.
    private let settings = Atomic<UInt8>(0)
    /// Touched only on the audio thread, between prepare and unprepare.
    private var processor: AudioAdjustmentProcessor?

    init(centreChannel: Int?) {
        self.centreChannel = centreChannel
    }

    func update(_ adjustments: AudioAdjustments) {
        let dialogue = AudioAdjustments.DialogueEnhancement.allCases.firstIndex(of: adjustments.dialogue) ?? 0
        settings.store(UInt8(dialogue) | (adjustments.reducesLoudSounds ? 4 : 0), ordering: .relaxed)
    }

    private var adjustments: AudioAdjustments {
        let packed = settings.load(ordering: .relaxed)
        let cases = AudioAdjustments.DialogueEnhancement.allCases
        let index = Int(packed & 3)
        return AudioAdjustments(
            dialogue: cases.indices.contains(index) ? cases[index] : .off,
            reducesLoudSounds: packed & 4 != 0
        )
    }

    /// The tap holds a reference to the context until it's finalized.
    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                AudioTapContext.from(tap).prepare(format.pointee)
            },
            unprepare: { tap in
                AudioTapContext.from(tap).processor = nil
            },
            process: { tap, frameCount, _, buffers, frameCountOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frameCount, buffers, flagsOut, nil, frameCountOut)
                    == noErr else { return }
                AudioTapContext.from(tap).process(buffers, frameCount: Int(frameCountOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let tap else {
            Unmanaged.passUnretained(self).release()
            return nil
        }
        return tap
    }

    private static func from(_ tap: MTAudioProcessingTap) -> AudioTapContext {
        Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    /// Only 32-bit float, one buffer per channel, is processed; anything else plays untouched.
    private func prepare(_ format: AudioStreamBasicDescription) {
        let flags = format.mFormatFlags
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              flags & kAudioFormatFlagIsFloat != 0, flags & kAudioFormatFlagIsNonInterleaved != 0 else {
            processor = nil
            return
        }
        let channels = Int(format.mChannelsPerFrame)
        processor = AudioAdjustmentProcessor(
            sampleRate: format.mSampleRate,
            channelCount: channels,
            centreChannel: centreChannel.flatMap { $0 < channels ? $0 : nil }
        )
    }

    private func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard processor != nil else { return }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        let count = list.count
        let adjustments = adjustments
        // A handful of pointers, on the stack: nothing allocates on the audio thread.
        withUnsafeTemporaryAllocation(of: UnsafeMutablePointer<Float>.self, capacity: count) { pointers in
            for index in 0..<count {
                guard let data = list[index].mData else { return }
                pointers[index] = data.assumingMemoryBound(to: Float.self)
            }
            // In place, so the processor's filter state isn't copied.
            processor?.process(UnsafeBufferPointer(pointers), frameCount: frameCount, adjustments: adjustments)
        }
    }
}
