import SwiftUI

/// Paging, reveal and layout state for the row preview gallery.
@MainActor
@Observable
final class RowPreviewModel {
    enum Mode { case browsing, controls }

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

    private let settleDelay: Duration
    private let swapDelay: Duration
    private var settleTask: Task<Void, Never>?
    private var swapTask: Task<Void, Never>?

    init(
        preview: RowPreview,
        settleDelay: Duration = Theme.RowPreview.settleDelay,
        swapDelay: Duration = Theme.RowPreview.infoSwapDelay
    ) {
        self.preview = preview
        let start = min(max(preview.startIndex, 0), preview.items.count - 1)
        index = start
        infoItem = preview.items[start]
        self.settleDelay = settleDelay
        self.swapDelay = swapDelay
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
        hideInfo()
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
            infoItem = current
        }
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
        isInfoVisible = false
    }

    private func settle() {
        guard infoItem.id != current.id else {
            isInfoVisible = true
            return
        }
        // Not swapped yet: swap now, and reveal a turn later so the two never share an animation.
        infoItem = current
        Task { [weak self] in self?.isInfoVisible = true }
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
