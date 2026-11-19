import Foundation

/// A subtitle track an add-on attached to a stream, or a subtitle add-on returned.
struct StreamSubtitle: Codable, Hashable, Sendable {
    let id: String?
    let url: String?
    /// ISO 639 code, e.g. `eng` or `en`.
    let lang: String?
    /// Release details OpenSubtitles adds, for matching a file to the stream.
    var subtitleFileName: String? = nil
    var movieReleaseName: String? = nil
    var releaseGroup: String? = nil
    var releaseFormat: String? = nil
    /// Frames per second times 1000; 0 when unknown.
    var fpsMilli: Int? = nil
}

extension StreamSubtitle {
    /// The release details are optional extras; a malformed one is dropped rather than the file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        lang = try? container.decodeIfPresent(String.self, forKey: .lang)
        subtitleFileName = try? container.decodeIfPresent(String.self, forKey: .subtitleFileName)
        movieReleaseName = try? container.decodeIfPresent(String.self, forKey: .movieReleaseName)
        releaseGroup = try? container.decodeIfPresent(String.self, forKey: .releaseGroup)
        releaseFormat = try? container.decodeIfPresent(String.self, forKey: .releaseFormat)
        fpsMilli = try? container.decodeIfPresent(Int.self, forKey: .fpsMilli)
    }
}
