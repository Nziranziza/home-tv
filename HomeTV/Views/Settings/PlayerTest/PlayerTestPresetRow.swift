import SwiftUI

/// One category of quick tests, as a row of cards.
struct PlayerTestPresetRow: View {
    let category: PlayerTestPreset.Category
    let counts: [String: Int]

    var body: some View {
        VStack(alignment: .leading) {
            RowHeader(title: "\(category.title) Tests")
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.stack * 2) {
                    ForEach(PlayerTestPreset.all.filter { $0.category == category && (counts[$0.id] ?? 0) > 0 }) { preset in
                        NavigationLink(value: PlayerTestRoute.preset(preset.id)) {
                            PlayerTestPresetCard(preset: preset, count: counts[preset.id] ?? 0)
                        }
                        .buttonStyle(SettingsCardStyle())
                        .frame(width: 400)
                    }
                }
                .padding(.vertical, Theme.Spacing.stack)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

private struct PlayerTestPresetCard: View {
    let preset: PlayerTestPreset
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: preset.symbol).font(.title3)
                Spacer()
                Text("\(count.formatted()) files").font(.caption).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            Text(preset.title).font(.headline)
            Text(preset.summary)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2, reservesSpace: true)
        }
        .foregroundStyle(theme.primaryText)
        .frame(height: 170)
    }
}
