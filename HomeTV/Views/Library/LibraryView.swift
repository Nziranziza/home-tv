import SwiftUI

/// Library tab. When signed in to Trakt it shows the user's Continue Watching (in-progress playback
/// scrobbled by any connected player) and Watchlist, sourced from `TraktService`'s caches. Signed
/// out, it points the user at Settings.
struct LibraryView: View {
    @State private var trakt = TraktService.shared
    @State private var selection: MetaPreview?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Color.background.ignoresSafeArea()

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
                        .padding(.horizontal, Theme.Row.contentInset)

                    if !trakt.continueWatchingItems.isEmpty {
                        metaRow(title: "Continue Watching", items: trakt.continueWatchingItems)
                    }
                    if !trakt.watchlistItems.isEmpty {
                        metaRow(title: "Watchlist", items: trakt.watchlistItems)
                    }
                }
                .padding(.vertical, 60)
            }
        }
    }

    private func metaRow(title: String, items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Color.primaryText)
                .padding(.horizontal, Theme.Row.contentInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Row.posterCardSpacing) {
                    ForEach(items) { meta in
                        ContentCard(meta: meta) { selection = meta }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Row.posterVerticalPadding)
            }
            .frame(height: Theme.Row.posterHeight)
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private var emptyLibrary: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.4))
            Text("Your Library is empty")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
            Text("Add titles to your Trakt watchlist, or resume something you've started elsewhere.")
                .font(.title3)
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var placeholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.4))
            Text("Library")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
            Text("Connect Trakt in Settings to see your watchlist and continue watching here.")
                .font(.title3)
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
