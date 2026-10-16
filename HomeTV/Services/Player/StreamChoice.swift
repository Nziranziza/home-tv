import Foundation

/// The stream a title was last launched with, kept by identity rather than URL: debrid and add-on URLs
/// expire between launches, so a resume fetches the streams again and picks this one back out.
struct StreamChoice: Codable, Hashable, Sendable {
    /// The movie or episode it was chosen for.
    let contentID: String
    let addonID: String
    let bingeGroup: String?
    let infoHash: String?
    let fileIdx: Int?
    let filename: String?
    /// The release line of the title, without the seeders and debrid tag that change between fetches.
    /// nil when the add-on gave no title to identify the file by.
    let releaseName: String?

    init(stream: Stream, addonID: String, contentID: String) {
        self.contentID = contentID
        self.addonID = addonID
        bingeGroup = stream.behaviorHints?.bingeGroup
        infoHash = stream.infoHash?.lowercased()
        fileIdx = stream.fileIdx
        filename = stream.behaviorHints?.filename
        releaseName = Self.releaseName(of: stream)
    }

    /// A shared display name or the "Stream" placeholder would match other files, so only a title counts.
    private static func releaseName(of stream: Stream) -> String? {
        guard let title = stream.title, !title.isEmpty else { return nil }
        let name = StreamMeta.make(from: stream).releaseName
        return name == "Stream" ? nil : name
    }

    /// The stream among `candidates`, fetched for `contentID`, that continues this choice. The same
    /// episode looks for the same file; any other episode looks for the same release, as the season
    /// queue does.
    func match(for contentID: String, among candidates: [SeasonQueueBuilder.Candidate]) -> Stream? {
        let identities = SeasonQueueBuilder.identities(bingeGroup: bingeGroup, infoHash: infoHash)
        let release = SeasonQueueBuilder.sameRelease(as: identities, addonID: addonID, among: candidates)
        guard contentID == self.contentID else { return release }
        return sameFile(among: candidates) ?? release
    }

    /// Uncached debrid links are skipped: Infuse would open them with nothing to play, and the picker
    /// is the better place to land.
    private func sameFile(among candidates: [SeasonQueueBuilder.Candidate]) -> Stream? {
        let own = candidates
            .filter {
                $0.addonID == addonID
                    && $0.stream.playableURL != nil
                    && !SeasonQueueBuilder.awaitsDebridDownload($0.stream)
            }
            .map(\.stream)
        if let infoHash, let match = own.first(where: { $0.infoHash?.lowercased() == infoHash && $0.fileIdx == fileIdx }) {
            return match
        }
        if let filename, let match = own.first(where: { $0.behaviorHints?.filename == filename }) {
            return match
        }
        guard let releaseName else { return nil }
        return own.first { Self.releaseName(of: $0) == releaseName && !contradicts($0) }
    }

    /// A differing filename or hash means another file, whatever the title says.
    private func contradicts(_ stream: Stream) -> Bool {
        if let filename, let other = stream.behaviorHints?.filename, other != filename { return true }
        if let infoHash, let other = stream.infoHash?.lowercased(), other != infoHash { return true }
        return false
    }
}
