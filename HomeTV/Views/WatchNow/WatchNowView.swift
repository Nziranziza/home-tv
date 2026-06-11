import SwiftUI

struct WatchNowView: View {
    @State private var model = WatchNowViewModel()
    @State private var history = WatchHistory.shared
    @State private var trakt = TraktService.shared
    @State private var selection: MetaPreview? = WatchNowView.initialSelection()
    @State private var streamRequest: StreamRequest?
    @Namespace private var contentFocus
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Full-screen hero. It's a clean full-width focus section above the rows
                        // (Down from the tab bar lands in it), with its own focus scope defaulting to
                        // Play.
                        HeroShelf(
                            items: model.heroItems,
                            defaultFocusNamespace: contentFocus,
                            onSelect: { meta in selection = meta },
                            onPlay: { meta in play(meta) },
                            onInfo: { meta in selection = meta }
                        )
                        .containerRelativeFrame(.vertical)
                        .focusSection()
                        .focusScope(contentFocus)

                        if !continueWatchingItems.isEmpty {
                            ContinueWatchingRow(items: continueWatchingItems) { item in
                                selection = item.preview
                            }
                            .padding(.top, Theme.WatchNow.interRowSpacing)
                        }

                        ForEach(model.rowSpecs) { spec in
                            ContentRow(spec: spec) { meta in
                                selection = meta
                            }
                            .padding(.top, Theme.WatchNow.interRowSpacing)
                        }
                    }
                    .padding(.bottom, Theme.WatchNow.bottomPadding)
                }
                .ignoresSafeArea()
                .contentMargins(.top, 0, for: .scrollContent)

                if model.hasNoAddons {
                    emptyState
                }
            }
            .task(id: model.rowSpecs.first?.id) {
                await model.loadHero()
            }
            .metaDetailDestinations(selection: $selection)
            .streamPickerCover(request: $streamRequest)
        }
    }

    /// Continue Watching source: Trakt's playback progress when signed in (authoritative across
    /// devices), otherwise the local watch history recorded when you tap Play in HomeTV.
    private var continueWatchingItems: [WatchHistoryItem] {
        if trakt.isSignedIn {
            return trakt.continueWatchingItems.map { WatchHistoryItem(preview: $0) }
        }
        return history.items
    }

    /// Hero Play: record the title in history and open the stream picker directly (same flow as the
    /// detail screen's Play button), instead of only navigating to the detail page.
    private func play(_ meta: MetaPreview) {
        history.record(
            typeID: meta.type,
            metaID: meta.id,
            name: meta.name,
            poster: meta.poster,
            background: meta.background,
            logo: meta.logo
        )
        streamRequest = StreamRequest(
            type: meta.type,
            contentID: meta.id,
            title: meta.name,
            backgroundURL: meta.background,
            logoURL: meta.logo
        )
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Text("No addons installed")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.primaryText)
            Text("Add a Stremio addon from Settings to start browsing.")
                .font(.title3)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private static func initialSelection() -> MetaPreview? {
        guard let raw = ProcessInfo.processInfo.environment["INITIAL_DETAIL"] else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return MetaPreview(
            id: parts[1],
            type: parts[0],
            name: "Loading…",
            poster: nil,
            posterShape: nil,
            background: nil,
            logo: nil,
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil
        )
    }
}
