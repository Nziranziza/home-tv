/// A release's group, source and resolution, read from a name like `Movie.2019.1080p.BluRay.x264-GROUP`.
struct SubtitleRelease: Equatable {
    enum Source: Equatable {
        case bluRay
        case web
        case tv
        case dvd
    }

    var group: String?
    var source: Source?
    /// Vertical lines, e.g. 1080.
    var resolution: Int?

    init(group: String? = nil, source: Source? = nil, resolution: Int? = nil) {
        self.group = group
        self.source = source
        self.resolution = resolution
    }

    init(name: String) {
        let lowered = name.lowercased()
        let tokens = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        source = tokens.lazy.compactMap(Self.source(for:)).first
        resolution = tokens.lazy.compactMap(Self.resolution(for:)).first
        group = Self.group(in: name)
    }

    private static func source(for token: String) -> Source? {
        switch token {
        case "bluray", "bdrip", "brrip", "bdremux", "remux", "bd": .bluRay
        case "web", "webdl", "webrip", "amzn", "nf", "dsnp", "hmax", "atvp": .web
        case "hdtv", "pdtv", "dsr", "dsrip", "tvrip", "sdtv": .tv
        case "dvd", "dvdrip", "dvdr", "dvd5", "dvd9": .dvd
        default: nil
        }
    }

    private static func resolution(for token: String) -> Int? {
        if token == "4k" || token == "uhd" { return 2160 }
        guard token.count >= 4, token.last == "p" || token.last == "i" else { return nil }
        return Int(token.dropLast()).flatMap { [480, 576, 720, 1080, 2160].contains($0) ? $0 : nil }
    }

    /// The word after the last `-`, e.g. `GROUP` in `x264-GROUP.mkv`. Not a source or resolution
    /// written with a dash, like `WEB-DL`.
    private static func group(in name: String) -> String? {
        var base = Substring(name)
        if let dot = base.lastIndex(of: "."), base.distance(from: dot, to: base.endIndex) <= 5 {
            base = base[..<dot]
        }
        guard let dash = base.lastIndex(of: "-") else { return nil }
        let group = base[base.index(after: dash)...].prefix { $0.isLetter || $0.isNumber }.lowercased()
        guard group.count >= 2, group.contains(where: \.isLetter) else { return nil }
        let before = String(base[..<dash].reversed().prefix { $0.isLetter || $0.isNumber }.reversed()).lowercased()
        guard source(for: before + group) == nil, source(for: group) == nil, resolution(for: group) == nil else {
            return nil
        }
        return group
    }
}
