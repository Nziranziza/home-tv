import Foundation

/// A request to present the stream picker for a movie or a specific series episode. Created by the
/// detail hero / episode rows and by the Watch Now hero's Play button, and consumed by
/// `StreamPickerView` via a `fullScreenCover`.
struct StreamRequest: Identifiable, Hashable {
    let type: String
    let contentID: String
    let title: String
    var backgroundURL: String? = nil
    var logoURL: String? = nil
    var id: String { "\(type):\(contentID)" }
}
