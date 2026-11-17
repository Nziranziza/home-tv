import Foundation
import Testing
@testable import HomeTV

/// Picture in Picture: the play outlives its screen in the corner, and comes back to it on expand.
@MainActor
struct PlayerPictureInPictureTests {
    static let item = PlaybackItem(contentID: "tt1160419", showID: "tt1160419")

    let presenter = PlayerPresenter()
    let engine = FakePlaybackEngine()
    /// Saved positions, in seconds.
    let saves = Saves()

    final class Saves {
        var positions: [Int] = []
    }

    /// A playing model on screen, as `PlayerScreen` would hold it.
    func makePlayingModel(url: URL = URL(filePath: "/streams/Dune.mkv")) -> PlayerModel {
        let request = PlayerRequest(url: url, title: "Dune", item: Self.item)
        let model = PlayerModel(
            request: request,
            engine: engine,
            publishesNowPlaying: false,
            recordProgress: { [saves] position, _, _ in saves.positions.append(position) },
            scrobble: { _ in },
            presenter: presenter
        )
        presenter.present(request)
        model.start()
        engine.duration = 3600
        engine.currentTime = 120
        model.playbackDidChange()
        return model
    }

    @Test func enteringTheCornerClosesTheScreenButKeepsPlaying() {
        let model = makePlayingModel()
        model.startPictureInPicture()

        #expect(presenter.request == nil)
        #expect(presenter.pictureInPicture === model)
        #expect(presenter.isPlaybackActive)
        #expect(model.isInPictureInPicture)
        #expect(!engine.isStopped)
    }

    @Test func expandingReopensTheSamePlay() throws {
        let model = makePlayingModel()
        model.startPictureInPicture()

        var restored: Bool?
        engine.expandPictureInPicture { restored = $0 }
        let request = try #require(presenter.request)
        #expect(request.id == model.request.id)
        #expect(presenter.model(for: request) === model)
        // AVKit waits for the screen before animating the corner into it.
        #expect(restored == nil)

        presenter.playerDidAppear(model)
        #expect(restored == true)

        engine.endPictureInPicture()
        #expect(!model.isInPictureInPicture)
        #expect(presenter.pictureInPicture == nil)
        #expect(!engine.isStopped)
    }

    @Test func closingTheCornerSavesAndStops() {
        let model = makePlayingModel()
        model.startPictureInPicture()
        engine.currentTime = 300

        engine.endPictureInPicture()
        #expect(saves.positions.last == 300)
        #expect(engine.isStopped)
        #expect(presenter.pictureInPicture == nil)
        #expect(!presenter.isPlaybackActive)
        #expect(!model.isInPictureInPicture)
    }

    @Test func anotherTitleReplacesTheCorner() {
        let model = makePlayingModel()
        model.startPictureInPicture()

        let next = PlayerRequest(url: URL(filePath: "/streams/Arrival.mkv"), title: "Arrival")
        presenter.present(next)
        #expect(engine.isStopped)
        #expect(engine.pictureInPictureStops == 1)
        #expect(presenter.pictureInPicture == nil)
        #expect(presenter.request?.id == next.id)
        #expect(presenter.model(for: next) !== model)
    }

    @Test func theCornerClosesWhenThePlayEnds() {
        let model = makePlayingModel()
        model.startPictureInPicture()

        engine.onFinish?(nil)
        #expect(engine.isStopped)
        #expect(presenter.pictureInPicture == nil)
        #expect(saves.positions.last == 3600)
    }
}
