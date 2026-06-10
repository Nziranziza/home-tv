import SwiftUI

/// Where the title is available to watch (TMDB/JustWatch, US), grouped by Stream / Rent / Buy. Purely
/// informational — playback still happens via addons; this just tells the user where the title
/// officially lives. Hidden entirely when TMDB has no availability for it.
struct DetailHowToWatchSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    @Environment(\.openURL) private var openURL

    /// Three flexible columns; the grid grows downward and the page scroll view handles vertical paging.
    private var howToWatchColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 30), count: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "How to Watch", scroll: scroll)
            LazyVGrid(columns: howToWatchColumns, spacing: 30) {
                ForEach(model.vm.watchOptions) { option in
                    WatchProviderCard(provider: option.provider, availability: option.availability) {
                        if let link = model.enrichment?.watchLink { openURL(link) }
                    }
                }
            }
            .padding(.horizontal, Theme.Detail.leftInset)
        }
        .focusSection()
    }
}
