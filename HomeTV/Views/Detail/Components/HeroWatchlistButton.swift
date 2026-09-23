import SwiftUI

/// The hero's watchlist toggle: a plus that becomes a checkmark once the title is saved.
///
/// Backed by Trakt when it is connected and by the local library otherwise, so the control does the
/// same thing either way — it used to be inert when signed out.
///
/// Shared by the title detail hero and the episode hero, which toggle the same show/movie.
struct HeroWatchlistButton: View {
    /// The whole preview, not just an id: saved locally the list has to render without re-fetching.
    let preview: MetaPreview

    var body: some View {
        let saved = UserLibrary.isInWatchlist(id: preview.id)
        HeroCircleButton(
            icon: saved ? "checkmark" : "plus",
            accessibilityLabel: saved ? "Remove from Watchlist" : "Add to Watchlist"
        ) {
            UserLibrary.toggleWatchlist(preview)
        }
    }
}
