import AVFoundation

/// The shared `.playback` / `.moviePlayback` audio session for every in-app video surface.
@MainActor
enum PlaybackAudioSession {
    private static var isConfigured = false

    /// Configures the session once per app run. A failure leaves it retryable.
    static func configure() {
        guard !isConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            isConfigured = true
        } catch {}
    }
}
