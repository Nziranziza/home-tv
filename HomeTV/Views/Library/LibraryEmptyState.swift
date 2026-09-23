import SwiftUI

/// Nothing saved yet — points back at Watch Now to go find something.
///
/// The action is not decoration: a tvOS screen with nothing focusable is a dead end — focus has
/// nowhere to land, so the screen swallows every press and Left never reaches the sidebar.
struct LibraryEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("Your Library is empty", systemImage: "books.vertical")
        } description: {
            Text("Add titles to your watchlist, or resume something you've started.")
        } actions: {
            Button("Browse Watch Now", systemImage: "play.circle") {
                DeepLinkRouter.shared.requestedTab = 0
            }
        }
    }
}
