import SwiftUI

/// The title detail screen: a near-full-height hero that collapses into a browse layout as you scroll,
/// over a fixed page backdrop, with the episode / trailer / related / cast / info rows beneath.
///
/// This is a thin container. The content state and the expensive episode/season derivations live in an
/// `@Observable` `MetaDetailModel` (computed once, not per render). The collapse clock lives in an
/// `@Observable` `DetailScrollState`, read only by the chrome (background, hero, centered logo, the
/// section-header fades) — so a scroll tick never re-evaluates the heavy episode strip or the other
/// content rows. Each visual section is its own `View` struct.
struct MetaDetailView: View {
    let typeID: String
    let metaID: String
    let fallbackTitle: String
    /// Preview/sample injection only. When set, the screen renders this title instead of loading from
    /// addons — used by `#Preview` so the demo can match the reference clip offline. nil in the app.
    var previewMeta: Meta?

    /// Content + memoized derivations + the async loaders (see `MetaDetailModel`).
    @State private var model: MetaDetailModel
    /// The hero↔browse collapse clock; only the chrome views read it.
    @State private var scroll = DetailScrollState()
    @State private var trakt = TraktService.shared
    @State private var streamRequest: StreamRequest?
    @State private var relatedSelection: MetaPreview?
    /// Set when a Cast & Crew headshot is selected → pushes the person/cast screen.
    @State private var castSelection: CastPerson?
    /// Set when an episode's description is selected → pushes the single-episode detail screen.
    @State private var episodeSelection: Video?
    /// The inline hero trailer player (Trailerio). Owned here so it survives scroll/collapse and is torn
    /// down on disappear; the background and hero observe it.
    @State private var trailerController = TrailerPlaybackController()
    /// Set when a Trailers-row card is selected → presents the full-screen in-app trailer player.
    @State private var trailerRequest: TrailerPlaybackRequest?
    @Environment(\.scenePhase) private var scenePhase

    /// Which region currently holds focus. Crossing the hero↔content boundary drives the full-viewport scroll.
    @FocusState private var zone: DetailZone?

    init(typeID: String, metaID: String, fallbackTitle: String, previewMeta: Meta? = nil) {
        self.typeID = typeID
        self.metaID = metaID
        self.fallbackTitle = fallbackTitle
        self.previewMeta = previewMeta
        _model = State(initialValue: MetaDetailModel(
            typeID: typeID, metaID: metaID, fallbackTitle: fallbackTitle, previewMeta: previewMeta
        ))
        _streamRequest = State(initialValue: MetaDetailView.initialStreamRequest())
    }

    private static func initialStreamRequest() -> StreamRequest? {
        guard let raw = ProcessInfo.processInfo.environment["INITIAL_STREAM_PICKER"] else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return StreamRequest(
            type: parts[0],
            contentID: parts[1],
            title: parts.count >= 3 ? parts[2] : "Stream Picker"
        )
    }

    var body: some View {
        // The shared detail shell (backdrop + collapse scroll + hero↔content zone scroll). This screen
        // supplies the ramped-blur background (sharp behind the hero, blurred behind the content) and the
        // full content column; the scaffold owns the tuned scroll/collapse machinery.
        DetailScaffold(scroll: scroll, zone: $zone) {
            DetailBackground(model: model, scroll: scroll, trailer: trailerController)
        } content: { proxy in
            DetailContent(
                model: model, scroll: scroll, trakt: trakt,
                streamRequest: $streamRequest, relatedSelection: $relatedSelection,
                castSelection: $castSelection, episodeSelection: $episodeSelection,
                trailerRequest: $trailerRequest, zone: $zone
            )
            .onChange(of: model.related.count) { _, newCount in
                if newCount > 0,
                   let target = ProcessInfo.processInfo.environment["SCROLL_TO"] {
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .task(id: "\(typeID):\(metaID)") { await model.load() }
        // Load this show's per-episode watched state from Trakt. The watched-shows sync gives only
        // show-level watched, so without this no episode would ever show a checkmark and the hero
        // up-next couldn't advance. Movies have no episode grid to fetch.
        .task(id: "episode-progress:\(metaID)") {
            if typeID == "series", trakt.isSignedIn {
                await trakt.loadEpisodeProgress(showIMDB: metaID)
            }
        }
        // Feed the loaded Trailerio sources to the inline hero player (autoplay is triggered by the
        // hero layer once it has a player and the hero is expanded). Empty → tear down.
        .onChange(of: model.trailerCandidates) { _, candidates in
            // Don't spin a player up if the hero is currently covered — the trailerCovered handler
            // will load it once the cover is dismissed.
            if candidates.isEmpty || trailerCovered {
                trailerController.teardown()
            } else {
                trailerController.load(candidates)
            }
        }
        // Covered by a pushed related detail, the stream picker, or the full-screen trailer player:
        // tear the inline trailer down to reclaim its decode buffer (these are "gone for a while"), and
        // reload it on return. (Scroll-collapse keeps the player alive instead — see DetailHeroTrailerLayer.)
        .onChange(of: trailerCovered) { _, covered in
            if covered {
                trailerController.teardown()
            } else if !model.trailerCandidates.isEmpty {
                trailerController.load(model.trailerCandidates)
            }
        }
        // Pause the trailer when the app is backgrounded; resume on return if the hero is still the
        // visible, uncovered, expanded surface.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !trailerCovered, scroll.p <= 0.12 { trailerController.play() }
                // Returning from an external player (which scrobbles to Trakt) re-pulls this show's
                // per-episode watched state, so the episode you just finished shows as watched.
                if typeID == "series", trakt.isSignedIn {
                    Task { await trakt.loadEpisodeProgress(showIMDB: metaID) }
                }
            } else {
                trailerController.pause()
            }
        }
        .onDisappear { trailerController.teardown() }
        .navigationDestination(item: $relatedSelection) { item in
            MetaDetailView(typeID: item.type, metaID: item.id, fallbackTitle: item.name)
        }
        .navigationDestination(item: $castSelection) { person in
            CastView(person: person)
        }
        .navigationDestination(item: $episodeSelection) { episode in
            EpisodeDetailView(model: model, episode: episode)
        }
        .streamPickerCover(request: $streamRequest)
        .trailerPlayerCover(request: $trailerRequest)
    }

    /// Whether something is covering the hero — a pushed related/episode detail, the stream picker, or
    /// the full-screen trailer player. Drives tearing the inline trailer down to free its buffer.
    private var trailerCovered: Bool {
        relatedSelection != nil || streamRequest != nil || trailerRequest != nil
            || castSelection != nil || episodeSelection != nil
    }
}

/// The scrolling content column. Reads only model content (never the scroll clock), so a scroll tick
/// doesn't re-evaluate it — only the chrome leaves inside each section (the headers, the season-selector
/// fade, the hero, the centered logo) re-render on scroll.
private struct DetailContent: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    @Binding var relatedSelection: MetaPreview?
    @Binding var castSelection: CastPerson?
    @Binding var episodeSelection: Video?
    @Binding var trailerRequest: TrailerPlaybackRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: DetailLayout.interSectionSpacing) {
            // The first content row carries `browseTopInset` of top padding so that, when the collapse
            // scrolls it to the top, it rests at ≈ y224 — clear of the pinned logo above it (State B).
            // The hero's negative bottom inset cancels that padding (and more) at rest so the bare card
            // still peeks below the hero in State A.
            DetailHeroSection(
                model: model, scroll: scroll, trakt: trakt,
                streamRequest: $streamRequest, zone: zone
            )
            .padding(.bottom, -(DetailLayout.heroBottomPull + DetailLayout.browseTopInset))

            // The first content row is the scroll/collapse target ("contentTop") and the row that peeks:
            // Episodes for a series, otherwise Trailers. The centered title logo occupies the
            // `browseTopInset` band above it, so it scrolls with the content and rests at the top in browse.
            if !model.seasons.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    DetailCenteredLogo(model: model, scroll: scroll)
                    DetailEpisodesSection(
                        model: model, scroll: scroll, trakt: trakt,
                        streamRequest: $streamRequest, episodeSelection: $episodeSelection, zone: zone
                    )
                }
                .id("contentTop")
                DetailTrailersSection(
                    model: model, scroll: scroll, trailerRequest: $trailerRequest, zone: zone
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    DetailCenteredLogo(model: model, scroll: scroll)
                    DetailTrailersSection(
                    model: model, scroll: scroll, trailerRequest: $trailerRequest, zone: zone
                )
                }
                .id("contentTop")
            }
            if !model.vm.relatedItems.isEmpty {
                DetailRelatedSection(model: model, scroll: scroll, relatedSelection: $relatedSelection)
                    .id("related")
            }
            if !model.watchOptions.isEmpty {
                DetailHowToWatchSection(model: model, scroll: scroll)
            }
            if !model.creditEntries.isEmpty {
                DetailCastSection(model: model, scroll: scroll, castSelection: $castSelection)
            }
            DetailAboutSection(model: model, scroll: scroll).id("about")
            DetailInformationSection(model: model).id("information")
        }
    }
}

// MARK: - Preview (PROPELLER sample — matches the reference clip; all values flow through the model)

#Preview("Detail — PROPELLER") {
    // Sample/preview data only. The film and every value tied to it are what shows in the reference
    // video; the running app feeds real dynamic data through the same model.
    let sample = Meta(
        id: "tt-propeller",
        type: "movie",
        name: "Propeller One-Way Night Coach",
        poster: nil,
        background: nil,
        logo: nil,
        description: "During the golden age of aviation, a young airplane enthusiast and his mother "
            + "embark on a cross-country journey to Hollywood—and their simple flight transforms into "
            + "the trip of a lifetime. A film by John Travolta.",
        releaseInfo: "2026",
        runtime: "1 hr",
        imdbRating: nil,
        genres: ["Drama"],
        cast: ["Clark Shotwell", "Kelly Eviston-Quinnett", "Ella Travolta"],
        director: ["John Travolta"],
        videos: nil
    )
    return NavigationStack {
        MetaDetailView(
            typeID: "movie",
            metaID: "tt-propeller",
            fallbackTitle: "Propeller One-Way Night Coach",
            previewMeta: sample
        )
    }
}
