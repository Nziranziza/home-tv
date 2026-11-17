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

    /// The play in the Picture in Picture corner, kept here once its screen closes.
    private(set) var pictureInPicture: PlayerModel?
    /// A corner play being expanded, until its screen is up.
    @ObservationIgnored private var restoring: (model: PlayerModel, completion: (Bool) -> Void)?

    /// True while playback is on screen.
    var isPresenting: Bool { request != nil }

    /// True while playback is on screen or in the corner, so surfaces stop their trailers.
    var isPlaybackActive: Bool { request != nil || pictureInPicture != nil }

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

    /// Replaces what's on screen, in place when the player is already up. Replaces the corner's play too.
    func present(_ request: PlayerRequest) {
        closePictureInPicture()
        self.request = request
    }

    /// The screen's model: the corner's when it's being expanded, else the prepared or a new one. Pure,
    /// since a view's init runs it.
    func model(for request: PlayerRequest) -> PlayerModel {
        if let restoring, restoring.model.request.id == request.id { return restoring.model }
        return PlayerPrewarmer.shared.take(for: request) ?? PlayerModel(request: request)
    }

    // MARK: - Picture in Picture

    /// The video reached the corner: the screen closes and the play lives on here.
    func enterPictureInPicture(_ model: PlayerModel) {
        pictureInPicture = model
        request = nil
    }

    /// Expand: the screen opens again on the same play, over the picker if one is up.
    func restorePictureInPicture(_ model: PlayerModel, completion: @escaping (Bool) -> Void) {
        guard pictureInPicture === model else { return completion(false) }
        pictureInPicture = nil
        restoring?.completion(false)
        restoring = (model, completion)
        request = model.request
    }

    /// The screen is up; AVKit animates the corner into it.
    func playerDidAppear(_ model: PlayerModel) {
        guard let restoring, restoring.model === model else { return }
        self.restoring = nil
        restoring.completion(true)
    }

    /// The corner closed by itself or from the remote. A restored play belongs to its screen by now.
    func pictureInPictureDidStop(_ model: PlayerModel) {
        guard pictureInPicture === model else { return }
        closePictureInPicture()
    }

    /// Ends the corner's play, saving its position.
    func closePictureInPicture() {
        guard let model = pictureInPicture else { return }
        pictureInPicture = nil
        model.stop()
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
