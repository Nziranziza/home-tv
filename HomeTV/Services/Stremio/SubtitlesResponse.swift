/// A subtitle add-on's answer to `subtitles/{type}/{id}.json`.
struct SubtitlesResponse: Codable, Sendable {
    let subtitles: [StreamSubtitle]?
}
