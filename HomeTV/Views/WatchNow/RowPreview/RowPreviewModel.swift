import Observation
import SwiftUI

/// Paging, reveal, trailer and layout state for the row preview gallery.
@MainActor
@Observable
final class RowPreviewModel {
    enum Mode { case browsing, controls }

    typealias DetailFactory = @MainActor (MetaPreview) -> MetaDetailModel
    typealias DetailLoader = @MainActor (MetaDetailModel) async -> Void

    let preview: RowPreview
    private(set) var index: Int
    /// False while the cards sit on the row (opening and closing), true once grown into the gallery.
    var isExpanded = false
    /// True once the grow has finished, so Watch Now can stop drawing under the opaque canvas.
    var coversWatchNow = false
    /// Browsing: Left/Right page the strip. Controls: focus is on the action buttons.
    var mode: Mode = .browsing
    /// The metadata overlay is hidden while the strip moves and revealed once it settles.
    private(set) var isInfoVisible = false
    /// The title the overlay shows. Only swapped while hidden, so text never changes over a moving card.
    private(set) var infoItem: MetaPreview
    /// The detail data behind `infoItem`: the same model, and so the same hero, as the detail screen.
    private(set) var infoDetail: MetaDetailModel
    /// The one inline trailer, played in the centred card.
    let trailer = TrailerPlaybackController()
    /// A detail push, the stream picker, the full-screen trailer or backgrounding. Stops the trailer.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            if isSuspended { stopTrailer() } else if isInfoVisible { startTrailer() }
        }
    }

    private let settleDelay: Duration
    private let swapDelay: Duration
    private let revealCap: Duration
    private let trailerDwell: Duration
    private let makeDetail: DetailFactory
    private let loadDetail: DetailLoader
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var swapTask: Task<Void, Never>?
    @ObservationIgnored private var capTask: Task<Void, Never>?
    @ObservationIgnored private var readyTask: Task<Void, Never>?
    @ObservationIgnored private var trailerTask: Task<Void, Never>?
    /// Settled, waiting on the current title's readiness or the cap.
    @ObservationIgnored private var isAwaitingReveal = false
    /// When the current title was paged to; the cap runs from here.
    @ObservationIgnored private var currentSince: ContinuousClock.Instant = .now
    /// Loaded (or loading) once per title, so paging back never fetches again.
    @ObservationIgnored private var details: [String: MetaDetailModel] = [:]

    init(
        preview: RowPreview,
        settleDelay: Duration = Theme.RowPreview.settleDelay,
        swapDelay: Duration = Theme.RowPreview.infoSwapDelay,
        revealCap: Duration = Theme.RowPreview.revealCap,
        trailerDwell: Duration = Theme.RowPreview.trailerDwell,
        makeDetail: @escaping DetailFactory = {
            // Related titles fill a movie's strip; a series shows episodes instead.
            MetaDetailModel(
                typeID: $0.type, metaID: $0.id, fallbackTitle: $0.name, seed: $0,
                loadsRelated: $0.type == "movie"
            )
        },
        loadDetail: @escaping DetailLoader = { await $0.load() }
    ) {
        self.preview = preview
        let start = min(max(preview.startIndex, 0), preview.items.count - 1)
        index = start
        infoItem = preview.items[start]
        self.settleDelay = settleDelay
        self.swapDelay = swapDelay
        self.revealCap = revealCap
        self.trailerDwell = trailerDwell
        self.makeDetail = makeDetail
        self.loadDetail = loadDetail
        let first = makeDetail(preview.items[start])
        infoDetail = first
        details[first.metaID] = first
        Task { await loadDetail(first) }
        loadAroundCurrent()
    }

    var items: [MetaPreview] { preview.items }
    var current: MetaPreview { items[index] }

    /// Cards kept mounted around the centre: the visible three plus one off each edge, so a slide
    /// always has its incoming card in place.
    var window: ClosedRange<Int> {
        max(0, index - 2)...min(items.count - 1, index + 2)
    }

    /// Pages by `delta`, clamped to the row. Returns false at an end.
    @discardableResult
    func advance(by delta: Int) -> Bool {
        let target = min(max(index + delta, 0), items.count - 1)
        guard target != index else { return false }
        index = target
        currentSince = .now
        hideInfo()
        loadAroundCurrent()
        scheduleSwap()
        scheduleSettle()
        return true
    }

    /// Swaps the overlay's title once it has faded out, in its own un-animated update. Swapping in the
    /// reveal's update instead cross-fades the outgoing title art over the new card, and a swap this
    /// early gives the new logo the whole slide to load.
    private func scheduleSwap() {
        swapTask?.cancel()
        swapTask = Task { [weak self, swapDelay] in
            guard (try? await Task.sleep(for: swapDelay)) != nil, let self else { return }
            swapInfo()
        }
    }

    private func swapInfo() {
        infoItem = current
        infoDetail = detail(for: current)
    }

    /// Reveals the overlay after `delay` (default `settleDelay`) of quiet; every page move restarts it.
    func scheduleSettle(after delay: Duration? = nil) {
        settleTask?.cancel()
        let delay = delay ?? settleDelay
        settleTask = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            self?.settle()
        }
    }

    func hideInfo() {
        settleTask?.cancel()
        capTask?.cancel()
        readyTask?.cancel()
        isAwaitingReveal = false
        isInfoVisible = false
        stopTrailer()
    }

    // MARK: Reveal gate

    /// Reveals once the current title's detail data is ready (the detail screen's own gate), or once
    /// `revealCap` has passed since it was paged to, whichever is first.
    private func settle() {
        isAwaitingReveal = true
        let detail = detail(for: current)
        if detail.isContentReady {
            reveal()
            return
        }
        let remaining = revealCap - (ContinuousClock.now - currentSince)
        capTask?.cancel()
        capTask = Task { [weak self] in
            guard (try? await Task.sleep(for: remaining)) != nil else { return }
            self?.reveal()
        }
        readyTask?.cancel()
        readyTask = Task { [weak self] in
            for await ready in Observations({ detail.isContentReady }) where ready {
                self?.reveal()
                return
            }
        }
    }

    private func reveal() {
        guard isAwaitingReveal else { return }
        isAwaitingReveal = false
        capTask?.cancel()
        readyTask?.cancel()
        guard infoItem.id != current.id else {
            showInfo()
            return
        }
        // Not swapped yet: swap now, and reveal a turn later so the two never share an animation.
        swapInfo()
        Task { [weak self] in self?.showInfo() }
    }

    private func showInfo() {
        isInfoVisible = true
        startTrailer()
    }

    // MARK: Detail data

    private func detail(for meta: MetaPreview) -> MetaDetailModel {
        if let existing = details[meta.id] { return existing }
        let detail = makeDetail(meta)
        details[meta.id] = detail
        Task { [loadDetail] in await loadDetail(detail) }
        return detail
    }

    /// The current title first, then its neighbours, so paging either way usually finds it loaded.
    private func loadAroundCurrent() {
        for i in [index, index + 1, index - 1] where items.indices.contains(i) {
            _ = detail(for: items[i])
        }
    }

    // MARK: Trailer

    /// Plays the revealed title's trailer in the card after a dwell, once its sources have loaded.
    private func startTrailer() {
        guard !isSuspended else { return }
        trailerTask?.cancel()
        let detail = infoDetail
        trailerTask = Task { [weak self, trailerDwell] in
            for await candidates in Observations({ detail.trailerCandidates }) where !candidates.isEmpty {
                guard let self, !isSuspended, isInfoVisible, infoDetail === detail else { return }
                trailer.load(candidates)
                trailer.autoplay(after: trailerDwell)
                return
            }
        }
    }

    /// Tears the player down at once, so at most one decoder is ever alive.
    func stopTrailer() {
        trailerTask?.cancel()
        trailer.teardown()
    }

    /// The playing trailer full screen, from the clip already on screen.
    var fullScreenTrailer: TrailerPlaybackRequest? {
        guard trailer.isReady else { return nil }
        return TrailerPlaybackRequest(title: infoItem.name, candidates: trailer.playbackOrder)
    }

    // MARK: Layout

    /// Card `i` in the gallery: the centred card spans the screen minus a peek and gap each side, sits
    /// below the top gutter and runs flush to the bottom edge.
    func galleryFrame(at i: Int, in screen: CGSize) -> CGRect {
        let inset = Theme.RowPreview.peek + Theme.RowPreview.gap
        let width = screen.width - 2 * inset
        let step = width + Theme.RowPreview.gap
        return CGRect(
            x: inset + CGFloat(i - index) * step,
            y: Theme.RowPreview.topGutter,
            width: width,
            height: screen.height - Theme.RowPreview.topGutter
        )
    }

    /// Card `i` back on the row, extrapolated from the picked card by the row's spacing. `lifted`
    /// grows the picked card to its focused size: true opening (it was focused), false closing (the
    /// real card underneath is unfocused, so at rest).
    func rowFrame(at i: Int, lifted: Bool = true) -> CGRect {
        let frame = preview.sourceFrame.offsetBy(dx: CGFloat(i - preview.startIndex) * preview.sourceStep, dy: 0)
        guard lifted, i == preview.startIndex else { return frame }
        let lift = Theme.RowPreview.sourceFocusLift
        return frame.insetBy(dx: -frame.width * (lift - 1) / 2, dy: -frame.height * (lift - 1) / 2)
    }

    /// Whether the current card's row slot is on screen to shrink back into. After paging past the
    /// visible part of the row it isn't, and the gallery fades out instead.
    func canCollapseIntoRow(screen: CGSize) -> Bool {
        CGRect(origin: .zero, size: screen).contains(rowFrame(at: index, lifted: false))
    }
}
