import SwiftUI

/// The catalog's sections, three to a row.
struct PlayerTestSectionGrid: View {
    let sections: [PlayerTestIndex.SectionInfo]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.stack * 2), count: 3)

    var body: some View {
        VStack(alignment: .leading) {
            RowHeader(title: "Browse the Catalog", subtitle: "Every file, as the samples were collected.")
            LazyVGrid(columns: columns, spacing: Theme.Spacing.stack * 2) {
                ForEach(sections) { section in
                    NavigationLink(value: PlayerTestRoute.section(section.id)) {
                        PlayerTestSectionCard(section: section)
                    }
                    .buttonStyle(SettingsCardStyle())
                }
            }
            .padding(.vertical, Theme.Spacing.stack)
            .focusSection()
        }
    }
}

private struct PlayerTestSectionCard: View {
    let section: PlayerTestIndex.SectionInfo
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(systemName: PlayerTestScope.symbol(forSection: section.id)).font(.title3)
                Spacer()
                PlayerTestExpectationBadge(expect: section.expect)
            }
            Text(section.title).font(.headline)
            Text(section.summary ?? "")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(3, reservesSpace: true)
            Spacer(minLength: 0)
            Text("\(section.itemCount.formatted()) files · \(section.groupCount.formatted()) groups")
                .font(.caption)
                .foregroundStyle(theme.tertiaryText)
        }
        .foregroundStyle(theme.primaryText)
        .frame(height: 250)
    }
}
