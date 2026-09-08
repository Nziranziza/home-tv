import SwiftUI

/// The hero's watchlist toggle: a plus that becomes a checkmark once the title is on the Trakt
/// watchlist. Signed out there is no watchlist to toggle, so it renders an inert Add to Up Next plus —
/// the control keeps its place in the row (and stays focusable) rather than the row reflowing on sign-in.
///
/// Shared by the title detail hero and the episode hero, which toggle the same show/movie.
struct HeroWatchlistButton: View {
    let trakt: TraktService
    let type: String
    let imdb: String

    var body: some View {
        if trakt.isSignedIn {
            let inWatchlist = trakt.isInWatchlist(imdb: imdb)
            HeroCircleButton(
                icon: inWatchlist ? "checkmark" : "plus",
                accessibilityLabel: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist"
            ) {
                trakt.toggleWatchlist(type: type, imdb: imdb)
            }
        } else {
            HeroCircleButton(icon: "plus", accessibilityLabel: "Add to Up Next") { }
        }
    }
}
