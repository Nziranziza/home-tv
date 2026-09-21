import SwiftUI

/// Cast & Crew hits: a row of circular headshots, naming only the focused one. Reuses the detail
/// screen's `CastChip`, so selecting a headshot pushes the same person screen from either place.
struct SearchCastSection: View {
    let people: [CastPerson]
    var onSelect: (CastPerson) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Cast & Crew", color: Theme.WatchNow.rowHeaderColor)
            ScrollView(.horizontal) {
                // Top-aligned like the detail row, so a focused chip's widened gap pushes its name
                // straight down instead of re-centering the whole row.
                LazyHStack(alignment: .top, spacing: Theme.Search.castSpacing) {
                    ForEach(people) { person in
                        CastChip(
                            name: person.name,
                            imageURL: person.profileURL,
                            avatarSize: Theme.Search.castAvatarSize,
                            labelsOnFocusOnly: true,
                            surface: .themed
                        ) {
                            onSelect(person)
                        }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Search.castRowPadding)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
