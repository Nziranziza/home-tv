import SwiftUI

/// One titled filmography row on the cast screen. Poster sections (films, crew work) use the shared
/// `ContentCard`; the landscape "Guest Appearances" section uses `CastTVCard` (thumbnail + caption).
struct CastFilmographyRow: View {
    let section: FilmographySection
    let onSelect: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(section.title)
                .font(.system(size: 30, weight: .semibold))
                // Same opaque grey the detail rows use (white@opacity over a bright blur reads too light).
                .foregroundStyle(Color(white: 0.6))
                .padding(.leading, CastLayout.rowInset)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: section.style == .poster ? 40 : 28) {
                    ForEach(section.items) { item in
                        card(for: item)
                    }
                }
                .padding(.horizontal, CastLayout.rowInset)
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
            .focusSection()
        }
    }

    @ViewBuilder
    private func card(for item: FilmographyItem) -> some View {
        switch section.style {
        case .poster:
            ContentCard(meta: item.preview, shape: .poster) { onSelect(item.preview) }
        case .landscape:
            CastTVCard(item: item) { onSelect(item.preview) }
        }
    }
}
