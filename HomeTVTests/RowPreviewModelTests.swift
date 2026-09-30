import CoreGraphics
import Testing
@testable import HomeTV

/// Paging, settle and layout for the row preview gallery.
@MainActor
struct RowPreviewModelTests {
    private let screen = CGSize(width: 1920, height: 1080)

    private func model(
        count: Int = 5,
        start: Int = 1,
        settleDelay: Duration = .milliseconds(60),
        swapDelay: Duration = .milliseconds(10),
        revealCap: Duration = .seconds(1),
        loader: @escaping RowPreviewModel.DetailLoader = { await $0.load() }
    ) -> RowPreviewModel {
        let items = (0..<count).map { Fixture.meta("Title \($0)") }
        let preview = RowPreview(
            items: items,
            startIndex: start,
            sourceFrame: CGRect(x: 384, y: 510, width: 260, height: 390),
            sourceStep: 296,
            sourceShape: .poster
        )
        return RowPreviewModel(
            preview: preview, settleDelay: settleDelay, swapDelay: swapDelay,
            revealCap: revealCap, makeDetail: Self.offlineDetail, loadDetail: loader
        )
    }

    @Test func opensOnThePickedTitle() {
        let model = model(start: 3)
        #expect(model.index == 3)
        #expect(model.infoItem.id == "Title 3")
    }

    @Test func pagingStopsAtBothEnds() {
        let model = model(count: 3, start: 0)
        #expect(!model.advance(by: -1))
        #expect(model.index == 0)
        #expect(model.advance(by: 1))
        #expect(model.advance(by: 1))
        #expect(!model.advance(by: 1))
        #expect(model.index == 2)
    }

    @Test func pagingHidesInfoBeforeSwappingTheTitle() {
        let model = model()
        model.advance(by: 1)
        #expect(!model.isInfoVisible)
        #expect(model.infoItem.id == "Title 1")
    }

    // Timing tests wait for the expected state rather than sleeping a fixed time, and leave hundreds
    // of milliseconds between a "still hidden" check and the reveal, so a slow runner can't flip them.

    @Test func theTitleSwapsWhileHiddenBeforeTheReveal() async throws {
        let model = model(settleDelay: .seconds(5))
        model.advance(by: 1)
        #expect(try await eventually { model.infoItem.id == "Title 2" })
        #expect(!model.isInfoVisible)
    }

    @Test func infoRevealsTheNewTitleOnceSettled() async throws {
        let model = model()
        model.advance(by: 1)
        #expect(try await eventually { model.isInfoVisible })
        #expect(model.infoItem.id == "Title 2")
    }

    @Test func eachMoveRestartsTheSettleWait() async throws {
        let model = model(settleDelay: .seconds(1))
        model.advance(by: 1)
        try await Task.sleep(for: .milliseconds(600))
        model.advance(by: 1)
        // 1.2s after the first move (its reveal would be due), but only 0.6s after the second.
        try await Task.sleep(for: .milliseconds(600))
        #expect(!model.isInfoVisible)
        #expect(try await eventually { model.isInfoVisible })
        #expect(model.infoItem.id == "Title 3")
    }

    // MARK: Reveal gate

    /// A detail model that loads from an in-memory meta, so `load()` settles at once without networking.
    private static func offlineDetail(_ meta: MetaPreview) -> MetaDetailModel {
        MetaDetailModel(
            typeID: meta.type, metaID: meta.id, fallbackTitle: meta.name, seed: meta,
            previewMeta: Meta(
                id: meta.id, type: meta.type, name: meta.name, poster: nil, background: nil, logo: nil,
                description: nil, releaseInfo: nil, runtime: nil, imdbRating: nil, genres: nil,
                cast: nil, director: nil, videos: nil
            ),
            loadsRelated: false
        )
    }

    @Test func revealWaitsForTheDetailData() async throws {
        let gate = LoaderGate()
        let model = model(revealCap: .seconds(10), loader: gate.load)
        model.advance(by: 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!model.isInfoVisible)
        gate.release()
        #expect(try await eventually { model.isInfoVisible })
        #expect(model.infoItem.id == "Title 2")
        #expect(model.infoDetail.isContentReady)
    }

    @Test func revealGoesAheadAtTheCap() async throws {
        let gate = LoaderGate()
        let model = model(revealCap: .milliseconds(300), loader: gate.load)
        model.advance(by: 1)
        #expect(try await eventually { model.isInfoVisible })
        #expect(model.infoItem.id == "Title 2")
        #expect(!model.infoDetail.isContentReady)
    }

    @Test func pagingBackReusesTheLoadedDetail() async throws {
        let counter = LoadCounter()
        let model = model(loader: counter.load)
        model.advance(by: 1)
        #expect(try await eventually { model.isInfoVisible })
        let seen = model.infoDetail
        model.advance(by: -1)
        model.advance(by: 1)
        #expect(try await eventually { model.isInfoVisible && model.infoItem.id == "Title 2" })
        #expect(model.infoDetail === seen)
        // Paging to 2 loads it, settling there adds 1's neighbour 3; back and forth fetches nothing new.
        #expect(counter.calls.sorted() == ["Title 1", "Title 2", "Title 3"])
    }

    @Test func neighboursLoadOnlyOnceSettled() async throws {
        let counter = LoadCounter()
        let model = model(settleDelay: .milliseconds(400), loader: counter.load)
        model.advance(by: 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.calls.sorted() == ["Title 1", "Title 2"])
        #expect(try await eventually { counter.calls.contains("Title 3") })
    }

    @Test func fastPagingCancelsTheTitlesPassedThrough() async throws {
        let gate = LoaderGate()
        let model = model(count: 10, start: 0, settleDelay: .seconds(5), loader: gate.load)
        for _ in 0..<5 { model.advance(by: 1) }
        // Only the centred titles start; each more than a page behind is cancelled, not queued.
        #expect(try await eventually { gate.started.count == 6 && gate.cancelled.count == 4 })
        #expect(gate.started.sorted() == (0...5).map { "Title \($0)" })
        #expect(gate.cancelled.sorted() == (0...3).map { "Title \($0)" })
        // A cancelled title loads afresh on a revisit.
        model.advance(by: -3)
        #expect(try await eventually { gate.started.filter { $0 == "Title 2" }.count == 2 })
    }

    @Test func noFullScreenTrailerUntilOneIsPlaying() {
        #expect(model().fullScreenTrailer == nil)
    }

    /// Polls `condition` until it holds or `timeout` passes.
    private func eventually(within timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func centredCardLeavesAPeekEachSide() {
        let model = model()
        let centre = model.galleryFrame(at: 1, in: screen)
        #expect(centre == CGRect(x: 120, y: 40, width: 1680, height: 1040))
        #expect(model.galleryFrame(at: 2, in: screen).minX == 1820)
        #expect(model.galleryFrame(at: 0, in: screen).maxX == 100)
    }

    @Test func rowFramesFollowTheRowSpacing() {
        let model = model()
        #expect(model.rowFrame(at: 2) == CGRect(x: 680, y: 510, width: 260, height: 390))
        // The picked card opens from its lifted (focused) size around the same centre…
        let picked = model.rowFrame(at: 1)
        #expect(picked.midX == 514)
        #expect(picked.width > 260)
        // …and closes onto its resting size, matching the unfocused card underneath.
        #expect(model.rowFrame(at: 1, lifted: false) == CGRect(x: 384, y: 510, width: 260, height: 390))
    }

    @Test func collapsesIntoTheRowOnlyWhileTheSlotIsOnScreen() {
        let model = model(count: 12, start: 1)
        #expect(model.canCollapseIntoRow(screen: screen))
        for _ in 0..<8 { model.advance(by: 1) }
        #expect(!model.canCollapseIntoRow(screen: screen))
    }

    @Test func windowKeepsTwoCardsEachSide() {
        let model = model(count: 10, start: 5)
        #expect(model.window == 3...7)
        let first = self.model(count: 10, start: 0)
        #expect(first.window == 0...2)
    }
}

/// A loader that holds every request until `release`, recording starts and cancellations.
@MainActor
private final class LoaderGate {
    private var isReleased = false
    private(set) var started: [String] = []
    private(set) var cancelled: [String] = []

    func load(_ detail: MetaDetailModel) async {
        started.append(detail.metaID)
        while !isReleased {
            guard (try? await Task.sleep(for: .milliseconds(10))) != nil else {
                cancelled.append(detail.metaID)
                return
            }
        }
        await detail.load()
    }

    func release() { isReleased = true }
}

/// A loader that records each title it is asked for.
@MainActor
private final class LoadCounter {
    private(set) var calls: [String] = []

    func load(_ detail: MetaDetailModel) async {
        calls.append(detail.metaID)
        await detail.load()
    }
}
