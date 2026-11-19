/// What subtitle add-ons are asked for: the title, and the file's name and fingerprint when the stream's
/// add-on gave them. The stream is never hashed here.
struct SubtitleAddonQuery: Hashable, Sendable {
    let type: String
    /// The movie's or the episode's id, e.g. `tt0903747:1:4`.
    let id: String
    var filename: String?
    var videoSize: Int64?
    var videoHash: String?

    /// The request's extra arguments, in the order Stremio sends them.
    var extra: [(name: String, value: String)] {
        [("videoHash", videoHash), ("videoSize", videoSize.map(String.init)), ("filename", filename)]
            .compactMap { name, value in value.map { (name, $0) } }
    }
}
