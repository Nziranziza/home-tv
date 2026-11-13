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
    /// Go to Movie / Go to Show's title, held while the stream picker under the player closes.
    private(set) var pendingDetail: MetaPreview?

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

    /// Where a player cover is attached: over the whole app, or over the stream picker.
    enum Site {
        case root
        case picker
    }

    /// The playback the cover at `site` shows.
    func request(at site: Site) -> PlayerRequest? {
        site == .root ? rootRequest : pickerRequest
    }

    /// Replaces what's on screen, in place when the player is already up.
    func present(_ request: PlayerRequest) {
        self.request = request
    }

    /// Go to Movie / Go to Show: closes the player, and the stream picker under it, then opens the title's
    /// detail screen in place of the stack, so Back doesn't return to the player.
    func goToDetail(_ meta: MetaPreview) {
        request = nil
        if isPickerUp {
            pendingDetail = meta
        } else {
            DeepLinkRouter.shared.openDetail(meta)
        }
    }

    func streamPickerDidAppear() {
        isPickerUp = true
    }

    /// `hostDetailID` is the detail screen the picker opened over, if any. Going to that same title just
    /// lands back on it.
    func streamPickerDidDismiss(hostDetailID: String?) {
        isPickerUp = false
        guard let meta = pendingDetail else { return }
        pendingDetail = nil
        if meta.id != hostDetailID { DeepLinkRouter.shared.openDetail(meta) }
    }
}
