import Foundation
import Observation

/// App-wide sink for incoming `hometv://` deep links (today: Top Shelf posters). Holds a pending
/// detail target plus the tab that should surface it; `RootTabView` and `WatchNowView` observe
/// these values and reset them to nil once consumed.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// The title a link wants opened in the detail screen. `WatchNowView` pushes it, then clears it.
    var pendingDetail: MetaPreview?

    /// The tab a link wants brought to the front (Watch Now hosts the detail navigation).
    var requestedTab: Int?

    private init() {}

    /// Parses links of the form `hometv://detail?type=movie&id=tt1234567&name=Title`. Unknown hosts
    /// or links missing `type`/`id` are ignored. The poster/background/logo are left nil — the
    /// detail screen loads full metadata from the id, exactly as the `INITIAL_DETAIL` launch path does.
    func handle(_ url: URL) {
        guard url.scheme == "hometv", url.host == "detail" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let type = items.first(where: { $0.name == "type" })?.value,
              let id = items.first(where: { $0.name == "id" })?.value else { return }
        let name = items.first(where: { $0.name == "name" })?.value ?? "Loading…"
        requestedTab = 0
        pendingDetail = .placeholder(type: type, id: id, name: name)
    }
}
