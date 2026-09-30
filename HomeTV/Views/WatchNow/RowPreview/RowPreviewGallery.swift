import SwiftUI

/// The row preview: a catalog row's titles as large backdrop cards on a dark canvas, paged with
/// Left/Right. Drawn over Watch Now rather than pushed, because it grows out of the row card (a tvOS
/// push always crossfades). Select or Info pushes the detail on top; Menu shrinks back into the row.
struct RowPreviewGallery: View {
    let model: RowPreviewModel
    /// A detail push or the stream picker is over the gallery.
    let isCovered: Bool
    let onPlay: (StreamRequest) -> Void
    let onInfo: (MetaPreview) -> Void
    /// The close animation has finished: remove the gallery and focus this row card, in one update.
    let onClosed: () -> Void

    enum Control: Hashable { case stage, action(DetailHeroAction), info, strip(Int) }

    @FocusState private var focus: Control?
    /// The full screen, in global coordinates; row frames are global too.
    @State private var bounds: CGRect = .zero
    @State private var isFadingOut = false
    /// Staged apart from the grow, as in the sample: art swaps and the canvas darkens on their own timing.
    @State private var showsCanvas = false
    @State private var showsSourceArt = true
    @State private var showsBackdrop = false
    @State private var isClosing = false
    @State private var trailerRequest: TrailerPlaybackRequest?
    /// An episode's description was selected in the strip: its detail is pushed over the gallery.
    @State private var episodeSelection: Video?
    @Environment(\.scenePhase) private var scenePhase

    private var screen: CGSize { bounds.size }

    var body: some View {
        Theme.RowPreview.canvas
            .opacity(showsCanvas ? 1 : 0)
            // Before `ignoresSafeArea`, which would report the safe-area frame instead.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds = $0 }
            // An overlay, so the cards (sized from `bounds`) can never resize what is measured.
            .overlay(alignment: .topLeading) {
                if screen != .zero {
                    ZStack(alignment: .topLeading) {
                        ForEach(model.window, id: \.self) { i in
                            card(at: i)
                        }
                        info
                        stage
                    }
                }
            }
            .ignoresSafeArea()
            .opacity(isFadingOut ? 0 : 1)
            .onExitCommand(perform: handleMenu)
            .onChange(of: focus) { _, new in
                if new == .stage { model.mode = .browsing }
            }
            .onChange(of: model.index) { _, _ in prefetchNeighbours() }
            .onChange(of: isCovered || trailerRequest != nil || episodeSelection != nil || scenePhase != .active, initial: true) { _, suspended in
                model.isSuspended = suspended
            }
            .onDisappear { model.stopTrailer() }
            .trailerPlayerCover(request: $trailerRequest)
            .navigationDestination(item: $episodeSelection) { episode in
                EpisodeDetailView(model: model.infoDetail, episode: episode)
            }
            .onChange(of: screen != .zero) { _, ready in
                // Deferred a turn so the cards first draw on the row, then grow from there.
                if ready { Task { open() } }
            }
    }

    // MARK: Cards

    private func card(at i: Int) -> some View {
        let frame = cardFrame(at: i)
        let isCentre = i == model.index
        return RowPreviewCard(
            meta: model.items[i],
            sourceShape: model.preview.sourceShape,
            showsSourceArt: showsSourceArt,
            showsBackdrop: showsBackdrop,
            loadsBackdrop: abs(i - model.index) <= 1,
            trailer: isCentre && model.isExpanded ? model.trailer : nil,
            dim: model.isExpanded && !isCentre ? Theme.RowPreview.neighbourDim : 0,
            topRadius: model.isExpanded ? Theme.RowPreview.cornerRadius : Theme.Radius.card,
            bottomRadius: model.isExpanded ? 0 : Theme.Radius.card
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .animation(Theme.RowPreview.slide, value: model.index)
    }

    /// In this view's coordinates.
    private func cardFrame(at i: Int) -> CGRect {
        guard model.isExpanded else {
            return model.rowFrame(at: i, lifted: !isClosing).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        }
        return model.galleryFrame(at: i, in: screen)
    }

    // MARK: Info + focus

    private var centreFrame: CGRect { model.galleryFrame(at: model.index, in: screen) }

    private var info: some View {
        RowPreviewInfoOverlay(
            detail: model.infoDetail,
            focus: $focus,
            areControlsEnabled: model.mode == .controls,
            onPlay: onPlay,
            onInfo: { onInfo(model.infoItem) },
            onOpenEpisode: { episodeSelection = $0 },
            onOpenRelated: { item in
                Task {
                    // Menu during the lookup closes the gallery; don't push over Watch Now afterwards.
                    guard let resolved = await DetailRelatedSection.resolved(item), !isClosing else { return }
                    onInfo(resolved)
                }
            },
            onExitControls: exitControls
        )
        .clipShape(.rect(topLeadingRadius: Theme.RowPreview.cornerRadius, topTrailingRadius: Theme.RowPreview.cornerRadius, style: .continuous))
        .frame(width: centreFrame.width, height: centreFrame.height)
        .offset(x: centreFrame.minX, y: centreFrame.minY)
        .opacity(model.isInfoVisible ? 1 : 0)
        .animation(model.isInfoVisible ? Theme.RowPreview.infoFadeIn : Theme.RowPreview.infoFadeOut, value: model.isInfoVisible)
    }

    /// Invisible focus target over the centred card. The only focusable while browsing, so Left/Right
    /// always reach it; edge strips keep Left and Up from escaping to the sidebar.
    private var stage: some View {
        Button { if !isClosing { onInfo(model.current) } } label: {
            Color.clear
        }
        .buttonStyle(RowPreviewStageButtonStyle())
        .focused($focus, equals: .stage)
        .onMoveCommand(perform: handleMove)
        .focusBarrier(.leading, isActive: focus == .stage || focus == nil, gap: 1) {
            if !isClosing { model.advance(by: -1) }
            Task { focus = .stage }
        }
        // Up while a trailer plays opens it full screen.
        .focusBarrier(.top, isActive: focus == .stage || focus == nil, gap: 1) {
            if !isClosing, let request = model.fullScreenTrailer { trailerRequest = request }
            Task { focus = .stage }
        }
        .frame(width: centreFrame.width, height: centreFrame.height)
        .offset(x: centreFrame.minX, y: centreFrame.minY)
        // Stays enabled through the close so focus stays parked here: disabling it mid-collapse sends
        // the focus engine searching the window while the cards move. Input is ignored via `isClosing`.
        .disabled(model.mode == .controls)
        .accessibilityLabel(model.current.name)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !isClosing else { return }
        switch direction {
        case .right: model.advance(by: 1)
        case .down: enterControls()
        default: break
        }
    }

    private func enterControls() {
        guard model.isInfoVisible, !isClosing else { return }
        model.mode = .controls
        Task { focus = .action(.play) }
    }

    private func exitControls() {
        model.mode = .browsing
        Task { focus = .stage }
    }

    // MARK: Open / close

    private func open() {
        prefetchNeighbours()
        withAnimation(Theme.RowPreview.growSpring) {
            model.isExpanded = true
        } completion: {
            // Menu during the grow retargets it into the close; don't reveal over a closing gallery.
            if !isClosing { model.scheduleSettle(after: Theme.RowPreview.openRevealDelay) }
        }
        // Watch Now stops drawing only once the canvas is fully opaque over it, which is after the grow.
        withAnimation(Theme.RowPreview.canvasFadeIn) {
            showsCanvas = true
        } completion: {
            if !isClosing { model.coversWatchNow = true }
        }
        withAnimation(Theme.RowPreview.sourceArtFadeOut) { showsSourceArt = false }
        withAnimation(Theme.RowPreview.backdropFadeIn) { showsBackdrop = true }
        focus = .stage
    }

    private func handleMenu() {
        if model.mode == .controls {
            exitControls()
        } else {
            close()
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        model.hideInfo()
        // Watch Now draws again under the still-opaque canvas, a beat before anything moves, so the
        // page's first frame back is not also the collapse's first frame.
        model.coversWatchNow = false
        Task {
            try? await Task.sleep(for: Theme.RowPreview.closeLeadIn)
            collapse()
        }
    }

    /// `.removed` completions: the gallery is torn down, and Watch Now re-enabled and its hero
    /// restarted, only once the motion has fully stopped, not on the spring's logical end mid-tail.
    private func collapse() {
        if model.canCollapseIntoRow(screen: screen) {
            withAnimation(Theme.RowPreview.collapseCurve, completionCriteria: .removed) {
                model.isExpanded = false
            } completion: {
                onClosed()
            }
            withAnimation(Theme.RowPreview.sourceArtFadeIn) { showsSourceArt = true }
            withAnimation(Theme.RowPreview.canvasFadeOut) { showsCanvas = false }
        } else {
            withAnimation(Theme.RowPreview.infoFadeIn, completionCriteria: .removed) {
                isFadingOut = true
            } completion: {
                onClosed()
            }
        }
    }

    private func prefetchNeighbours() {
        for i in model.window {
            let meta = model.items[i]
            if let url = RowPreviewCard.backdropURL(for: meta) {
                Task { await ImageLoader.shared.prefetch(url: url, targetSize: Theme.Hero.backdropTargetSize) }
            }
            if let url = RowPreviewInfoOverlay.logoURL(for: meta) {
                Task { await ImageLoader.shared.prefetch(url: url, targetSize: RowPreviewInfoOverlay.logoSize) }
            }
        }
    }
}

/// Draws nothing: the stage is felt, not seen — the centred card itself is the focus indication.
private struct RowPreviewStageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(.rect)
    }
}
