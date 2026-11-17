/// What an episode's next one must match to continue the same release: the add-on and the release
/// identity the season queue already uses.
struct EpisodeContinuation: Hashable, Sendable {
    let addonID: String
    let release: Set<SeasonQueueBuilder.ReleaseIdentity>

    /// Nil when the stream has no release identity to continue.
    init?(stream: Stream, addonID: String) {
        let release = SeasonQueueBuilder.identities(of: stream)
        guard !release.isEmpty, !addonID.isEmpty else { return nil }
        self.addonID = addonID
        self.release = release
    }
}
