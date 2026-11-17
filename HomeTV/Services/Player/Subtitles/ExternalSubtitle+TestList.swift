#if DEBUG
import Foundation

extension ExternalSubtitle {
    /// `PLAYER_TEST_SUBTITLES`: comma-separated files, each `<url or file in Caches>` with an optional
    /// `<language>=` prefix. A prefix holds no `/` or `.`, so a URL's own `=` stays in the URL.
    static func testList(from raw: String) -> [ExternalSubtitle] {
        raw.split(separator: ",").compactMap { entry in
            var language: String?
            var location = Substring(entry)
            if let equals = entry.firstIndex(of: "="),
               !entry[..<equals].contains(where: { $0 == "/" || $0 == "." }) {
                language = String(entry[..<equals])
                location = entry[entry.index(after: equals)...]
            }
            guard !location.isEmpty else { return nil }
            let path = String(location)
            let url = path.contains("://") ? URL(string: path) : URL.cachesDirectory.appending(path: path)
            return url.map { ExternalSubtitle(url: $0, languageCode: SubtitleLanguage.normalized(language)) }
        }
    }
}
#endif
