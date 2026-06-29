import SwiftUI

/// Cast & Crew row. With TMDB enrichment each chip shows a headshot + character/role; without it,
/// falls back to the addon's name-only cast + director (initials avatars).
struct DetailCastSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    /// Set when a cast headshot is selected → pushes the person/cast screen.
    @Binding var castSelection: CastPerson?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Cast & Crew", scroll: scroll)
            ScrollView(.horizontal) {
                // Top-aligned (like the episodes row) so a focused chip's widened gap pushes its
                // name+role straight down, instead of a centered row re-centering and eating the push.
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(model.vm.creditEntries) { entry in
                        CastChip(name: entry.name, role: entry.role, imageURL: entry.imageURL) {
                            // Only TMDB cast (with a person id) navigate into the cast screen;
                            // name-only crew entries are inert.
                            if let personID = entry.personID {
                                castSelection = CastPerson(id: personID, name: entry.name,
                                                           profileURL: entry.imageURL)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 16)
            }
            .detailRowScroll()
            .focusSection()
        }
    }
}
