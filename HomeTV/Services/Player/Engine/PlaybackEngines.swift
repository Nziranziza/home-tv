/// The engine for this build: KSPlayer on the Apple TV, the AVPlayer stub where KSPlayer has no slice.
@MainActor
enum PlaybackEngines {
    static func make() -> any PlaybackEngine {
        #if canImport(KSPlayer)
        KSPlaybackEngine()
        #else
        AVPlaybackEngine()
        #endif
    }
}
