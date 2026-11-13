import Foundation

/// Opens the focused stream picker row's stream before Select, so the player starts from a buffer.
/// Holds one play at a time; the player screen takes it when its request matches.
@MainActor
final class PlayerPrewarmer {
    static let shared = PlayerPrewarmer()

    private var model: PlayerModel?
    private let makeModel: @MainActor (PlayerRequest) -> PlayerModel

    init(makeModel: @escaping @MainActor (PlayerRequest) -> PlayerModel = { PlayerModel(request: $0) }) {
        self.makeModel = makeModel
    }

    /// Prepares `request`, replacing any other prepared play.
    func prewarm(_ request: PlayerRequest) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PLAYER_NO_PREWARM"] == "1" { return }
        #endif
        if let model, model.request.isSamePlay(as: request) { return }
        cancel()
        PlaybackDiagnostics.log("prewarm \(request.url.lastPathComponent)")
        let model = makeModel(request)
        self.model = model
        model.prepare()
    }

    /// Focus moved on: closes the prepared stream.
    func cancel() {
        model?.discard()
        model = nil
    }

    /// The prepared play for `request`, handed over once. Anything else prepared is closed.
    func take(for request: PlayerRequest) -> PlayerModel? {
        defer { model = nil }
        // A preparation that failed gets a fresh attempt instead.
        guard let model, model.request.isSamePlay(as: request), model.errorMessage == nil else {
            model?.discard()
            return nil
        }
        return model
    }
}
