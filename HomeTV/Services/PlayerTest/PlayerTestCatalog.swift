import Foundation

/// The sample library from issue #148: sections → groups → items. Fetched at runtime, never bundled.
struct PlayerTestCatalog: Decodable, Sendable {
    static let url = URL(string: "https://gist.githubusercontent.com/Nziranziza/3c1095a30345e9c65613704d98d6dd62/raw/player-test-catalog.json")

    let itemCount: Int
    /// The day the samples were verified, `2026-11-18`.
    let generated: String?
    let sections: [PlayerTestSection]

    static func decode(_ data: Data) throws -> PlayerTestCatalog {
        try JSONDecoder().decode(PlayerTestCatalog.self, from: data)
    }
}
