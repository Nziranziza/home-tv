import Observation

/// Presents the in-app player. Over the stream picker when it launched playback, so Back returns there;
/// over the whole app otherwise (Continue Watching). Only the topmost cover can present, so each
/// presentation site binds to its own view of `request`.
@Observable
@MainActor
final class PlayerPresenter {
    static let shared = PlayerPresenter()

    /// The playback on screen.
    var request: PlayerRequest?
    private var isPickerUp = false

    /// True while playback is on screen, so surfaces underneath stop their trailers.
    var isPresenting: Bool { request != nil }

    /// Bound to the root's cover.
    var rootRequest: PlayerRequest? {
        get { isPickerUp ? nil : request }
        set { request = newValue }
    }

    /// Bound to the stream picker's cover.
    var pickerRequest: PlayerRequest? {
        get { isPickerUp ? request : nil }
        set { request = newValue }
    }

    func present(_ request: PlayerRequest) {
        self.request = request
    }

    func streamPickerDidAppear() {
        isPickerUp = true
    }

    func streamPickerDidDismiss() {
        isPickerUp = false
    }
}
