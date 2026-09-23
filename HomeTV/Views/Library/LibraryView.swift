import SwiftUI

/// Library tab: the user's Continue Watching (in-progress playback) and Watchlist.
///
/// Sourced from Trakt when it is connected — where any connected player's scrobbles land — and from
/// this device otherwise. It used to be a Trakt-only screen that showed a Settings prompt when signed
/// out; now Trakt only makes the same screen sync across devices.
struct LibraryView: View {
    @State private var trakt = TraktService.shared
    @State private var history = WatchHistory.shared
    @State private var selection: MetaPreview?
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                LibraryContent(
                    continueItems: continueItems,
                    watchlistItems: UserLibrary.watchlistItems,
                    selection: $selection
                )
            }
            .metaDetailDestinations(selection: $selection)
            .task {
                if trakt.isSignedIn { await trakt.refreshLibrary() }
            }
        }
    }

    /// In-progress titles: Trakt's playback when signed in, the local history otherwise — the same
    /// rule Watch Now's Continue Watching row uses.
    private var continueItems: [MetaPreview] {
        trakt.isSignedIn ? trakt.continueWatchingItems : history.inProgressItems.map(\.preview)
    }
}
