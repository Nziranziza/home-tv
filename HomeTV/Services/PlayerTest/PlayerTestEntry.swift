import Foundation

/// An item with the section and group it sits in, searchable.
struct PlayerTestEntry: Identifiable, Equatable, Sendable {
    /// Position in the flattened catalog; a few URLs appear twice, so the URL can't be the id.
    let id: Int
    let item: PlayerTestItem
    let sectionID: String
    let sectionTitle: String
    let groupTitle: String
    let expect: PlayerTestExpectation
    let words: [String]

    init(id: Int, item: PlayerTestItem, sectionID: String, sectionTitle: String, groupTitle: String, expect: PlayerTestExpectation) {
        self.id = id
        self.item = item
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.groupTitle = groupTitle
        self.expect = expect
        var text = [item.title, item.filename, item.container, sectionTitle, groupTitle]
        for value in [item.video, item.audio, item.resolution, item.hdr].compactMap(\.self) {
            text += [value, PlayerTestVocabulary.aliases(value)]
        }
        words = PlayerTestSearch.words(text.joined(separator: " "))
    }

    var breadcrumb: String { "\(sectionTitle) › \(groupTitle)" }

    func matches(_ query: String) -> Bool {
        PlayerTestSearch.matches(PlayerTestSearch.tokens(query), words: words)
    }
}
