import SwiftUI

/// Library tab. When signed in to Trakt it shows the user's Continue Watching (in-progress playback
/// scrobbled by any connected player) and Watchlist, sourced from `TraktService`'s caches. Signed
/// out, it points the user at Settings.
struct LibraryView: View {
    @State private var trakt = TraktService.shared
    @State private var selection: MetaPreview?
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                if trakt.isSignedIn {
                    signedInContent
                } else {
                    placeholder
                }
            }
            .metaDetailDestinations(selection: $selection)
            .task {
                if trakt.isSignedIn { await trakt.refreshLibrary() }
            }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if trakt.continueWatchingItems.isEmpty && trakt.watchlistItems.isEmpty {
            emptyLibrary
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 48) {
                    ScreenTitle(title: "Library")
                        .padding(.horizontal, Theme.Layout.horizontalMargin)

                    if !trakt.continueWatchingItems.isEmpty {
                        metaRow(title: "Continue Watching", items: trakt.continueWatchingItems)
                    }
                    if !trakt.watchlistItems.isEmpty {
                        metaRow(title: "Watchlist", items: trakt.watchlistItems)
                    }
                }
                .padding(.vertical, 60)
            }
            .pageHorizontalInsets()
        }
    }

    private func metaRow(title: String, items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, Theme.Layout.horizontalMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta) { selection = meta }
                    }
                }
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.vertical, Theme.Row.posterVerticalPadding)
            }
            .frame(height: Theme.Row.posterHeight)
            .scrollClipDisabled()
        }
        .focusSection()
    }

    /// Signed in, nothing saved yet — points back at Watch Now to go find something.
    ///
    /// The action is not decoration: a tvOS screen with nothing focusable is a dead end — focus has
    /// nowhere to land, so the screen swallows every press and Left never reaches the sidebar.
    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your Library is empty", systemImage: "books.vertical")
        } description: {
            Text("Add titles to your Trakt watchlist, or resume something you've started elsewhere.")
        } actions: {
            Button("Browse Watch Now", systemImage: "play.circle") {
                DeepLinkRouter.shared.requestedTab = 0
            }
        }
    }

    /// Signed out — the only useful next step is connecting Trakt in Settings.
    private var placeholder: some View {
        ContentUnavailableView {
            Label("Library", systemImage: "books.vertical")
        } description: {
            Text("Connect Trakt in Settings to see your watchlist and continue watching here.")
        } actions: {
            Button("Open Settings", systemImage: "gearshape") {
                DeepLinkRouter.shared.requestedTab = 3
            }
        }
    }
}
