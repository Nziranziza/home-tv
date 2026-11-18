import Foundation

/// The catalog flattened for search, with the counts the home screen shows.
struct PlayerTestIndex: Sendable {
    struct SectionInfo: Identifiable, Sendable {
        let id: String
        let title: String
        let summary: String?
        let expect: PlayerTestExpectation
        let itemCount: Int
        let groupCount: Int
    }

    let entries: [PlayerTestEntry]
    let sections: [SectionInfo]
    let presetCounts: [String: Int]
    let verified: Date?

    init(_ catalog: PlayerTestCatalog) {
        var entries: [PlayerTestEntry] = []
        for section in catalog.sections {
            for group in section.groups {
                for item in group.items {
                    entries.append(PlayerTestEntry(
                        id: entries.count,
                        item: item,
                        sectionID: section.id,
                        sectionTitle: section.title,
                        groupTitle: group.title,
                        expect: item.expect ?? section.expect
                    ))
                }
            }
        }
        self.entries = entries
        sections = catalog.sections.map {
            SectionInfo(id: $0.id, title: $0.title, summary: $0.summary, expect: $0.expect,
                        itemCount: $0.itemCount, groupCount: $0.groups.count)
        }
        var counts: [String: Int] = [:]
        for preset in PlayerTestPreset.all {
            counts[preset.id] = entries.reduce(0) { $0 + (preset.matches($1) ? 1 : 0) }
        }
        presetCounts = counts
        verified = catalog.generated.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
    }

    func scope(for route: PlayerTestRoute) -> PlayerTestScope? {
        switch route {
        case .all:
            return PlayerTestScope(
                title: "All Files",
                summary: "Search by name, codec, container, HDR format, section or group.",
                symbol: "magnifyingglass",
                entries: entries
            )
        case .section(let id):
            guard let section = sections.first(where: { $0.id == id }) else { return nil }
            return PlayerTestScope(
                title: section.title,
                summary: section.summary ?? "",
                symbol: PlayerTestScope.symbol(forSection: id),
                entries: entries.filter { $0.sectionID == id }
            )
        case .preset(let id):
            guard let preset = PlayerTestPreset.preset(id: id) else { return nil }
            return PlayerTestScope(
                title: preset.title,
                summary: preset.summary,
                symbol: preset.symbol,
                entries: entries.filter(preset.matches)
            )
        case .local:
            return nil
        }
    }
}
