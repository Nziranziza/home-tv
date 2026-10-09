import SwiftUI

struct WatchNowView: View {
    /// Whether the Watch Now tab is the one currently on screen. `.sidebarAdaptable` keeps sibling tabs
    /// mounted, so this view keeps running off-tab; this flag lets the hero stand down when it isn't visible.
    var isSelectedTab: Bool = true

    @State private var model = WatchNowViewModel()
    @State private var history = WatchHistory.shared
    @State private var trakt = TraktService.shared
    @State private var path: [WatchNowRoute] = WatchNowView.initialPath()
    @State private var streamRequest: StreamRequest?
    @State private var router = DeepLinkRouter.shared
    /// Shared hero carousel state, read by the pinned backdrop and the scrolling overlay alike.
    @State private var heroModel = HeroCarouselModel()
    /// The open row preview, drawn over the page.
    @State private var rowPreview: RowPreviewModel?
    /// The row card a closed preview hands focus back to. While set, it is the page's only focusable.
    @State private var focusReturn: FocusReturn?
    @Environment(\.theme) private var theme

    /// Inactive while a detail is pushed or the stream picker modal is up, so the hero trailer isn't
    /// left decoding underneath either.
    private var isHeroActive: Bool { isSelectedTab && path.isEmpty && streamRequest == nil && rowPreview == nil }

    /// Everything but the returning card is disabled while focus lands on it.
    private var isFocusLocked: Bool { focusReturn != nil }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HeroSheetPage(
                    heroModel: heroModel,
                    showsHero: !model.hasNoAddons,
                    isHeroDisabled: isFocusLocked,
                    onPlay: { meta in play(meta) },
                    onInfo: { meta in path.append(.detail(meta)) }
                ) {
                    // Compute once — the guard and the row both read it.
                    let continueItems = continueWatchingItems
                    if !continueItems.isEmpty {
                        ContinueWatchingRow(items: continueItems) { item in
                            path.append(.detail(item.preview))
                        }
                        .disabled(isFocusLocked)
                    }

                    ForEach(model.rowSpecs) { spec in
                        ContentRow(
                            spec: spec,
                            onSelect: { rowPreview = RowPreviewModel(preview: $0) },
                            focusTarget: focusReturn?.rowID == spec.id ? focusReturn?.cardID : nil
                        )
                        .disabled(isFocusLocked && focusReturn?.rowID != spec.id)
                    }

                    // One card per streaming service, each pushing its channel screen.
                    ExploreChannelsRow { channel in
                        path.append(.channel(channel))
                    }
                    .disabled(isFocusLocked)

                    // What's new right now: in cinemas, or just landed to buy or rent. Sourced
                    // from TMDB because no addon catalog carries a release window, and it hides
                    // itself when that source has nothing. Sits below the catalogs and above
                    // Browse by Genre — the showcase cards are near twice a catalog poster, so
                    // leading with them would crowd out the rows the addons actually provide.
                    InTheatersRow { meta in
                        path.append(.detail(meta))
                    }
                    .disabled(isFocusLocked)

                    // The only row whose cards push a destination rather than a title.
                    BrowseByGenreRow { genre in
                        path.append(.genre(genre))
                    }
                    .disabled(isFocusLocked)

                    // Last row on the screen: what you've finished. Computed once for the same
                    // reason as `continueItems` above.
                    let recentItems = recentlyWatchedItems
                    if !recentItems.isEmpty {
                        RecentlyWatchedRow(items: recentItems) { item in
                            path.append(.detail(item.preview))
                        }
                        .disabled(isFocusLocked)
                    }
                }

                // Hidden once the preview's opaque canvas covers it, so it neither draws nor offers focus.
                .opacity(rowPreview?.coversWatchNow == true ? 0 : 1)
                .disabled(rowPreview != nil)

                if model.hasNoAddons {
                    emptyState
                }

                if let rowPreview {
                    RowPreviewGallery(
                        model: rowPreview,
                        isCovered: !path.isEmpty || streamRequest != nil,
                        onPlay: { streamRequest = $0 },
                        onInfo: { meta in path.append(.detail(meta)) },
                        onClosed: { close(rowPreview) }
                    )
                }
            }
            .task(id: model.rowSpecs.first?.id) {
                await model.loadHero()
                heroModel.items = model.heroItems
            }
            .onChange(of: isHeroActive, initial: true) { _, active in
                heroModel.isActive = active
            }
            // Cold launch from a Top Shelf poster: the link may already be pending before the first
            // render, so onChange would miss it. Consume any waiting target on appear.
            .task { consumePendingDetail() }
            // Warm path: a poster tapped while the app is running flips pendingDetail.
            .onChange(of: router.pendingDetail) { _, _ in consumePendingDetail() }
            .watchNowDestinations(
                path: $path,
                isStackVisible: isSelectedTab && streamRequest == nil,
                onPlay: { meta in play(meta) }
            )
            .streamPickerCover(request: $streamRequest)
        }
    }

    /// Continue Watching source: Trakt's playback progress when signed in (authoritative across
    /// devices), otherwise the local watch history recorded when you tap Play in HomeTV.
    private var continueWatchingItems: [WatchHistoryItem] {
        if trakt.isSignedIn {
            return trakt.continueWatchingItems
        }
        return history.inProgressItems
    }

    /// Recently Watched source, mirroring Continue Watching above: Trakt's finished history when signed
    /// in (episode-level, with real runtimes), otherwise the local history's finished items.
    private var recentlyWatchedItems: [RecentlyWatchedItem] {
        if trakt.isSignedIn {
            return trakt.recentlyWatchedItems
        }
        return history.finishedItems.map(RecentlyWatchedItem.init(finished:))
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

    /// Removes the gallery with the closed-on card as the page's only focusable, so tvOS's fallback for
    /// the lost focus can only land there. A programmatic request can't: tvOS drops one from a row that
    /// doesn't contain the focused item, and the gallery's stage is outside every row.
    private func close(_ preview: RowPreviewModel) {
        // A deep link may already have dismissed it mid-close.
        guard rowPreview === preview else { return }
        let target = FocusReturn(rowID: preview.preview.rowID, cardID: preview.current.id)
        focusReturn = target
        rowPreview = nil
        Task {
            try? await Task.sleep(for: Theme.RowPreview.focusLockHold)
            if focusReturn == target { focusReturn = nil }
        }
    }

    /// Presents the detail screen for a deep-linked title, if one is waiting. Replacing the whole
    /// navigation path makes this work from any state: cold launch (empty path), warm with nothing
    /// open, and — crucially — warm while another detail is already on the stack (the user opened one,
    /// pressed Home, then chose a Top Shelf poster). A path is a value collection, so swapping its
    /// contents always takes effect, unlike `navigationDestination(item:)` which ignores value→value.
    private func consumePendingDetail() {
        guard let pending = router.pendingDetail else { return }
        router.pendingDetail = nil
        rowPreview = nil
        focusReturn = nil
        path = [.detail(pending)]
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

    private static func initialPath() -> [WatchNowRoute] {
        guard let raw = ProcessInfo.processInfo.environment["INITIAL_DETAIL"] else { return [] }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        return [.detail(.placeholder(type: parts[0], id: parts[1]))]
    }
}
