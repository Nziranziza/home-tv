import Foundation

/// The tiny slice of app state the out-of-process Top Shelf extension needs but can't discover on its
/// own. The extension fetches the public Cinemeta catalog directly, but trailer autoplay needs the
/// user's installed **Trailerio** addon — which lives in `AddonRegistry` under `UserDefaults.standard`,
/// unreachable from the extension. This bridges the one value across the shared App Group container.
///
/// Written by the app (`AddonRegistry`) whenever the addon list changes; read by the Top Shelf
/// `ContentProvider`. A `nil` value means Trailerio isn't installed, so the extension keeps its
/// static-poster carousel exactly as before.
///
/// Stored as an absolute string rather than via `UserDefaults.set(_ url:)`, which archives a bookmark
/// for URLs and behaves inconsistently across processes.
enum TopShelfSharedState {
    /// The App Group both the app and the Top Shelf extension are entitled to (see the `.entitlements`).
    private static let suiteName = "group.com.hometv.HomeTVs"
    private static let trailerioBaseKey = "hometv.topshelf.trailerioBase.v1"

    private static let defaults = UserDefaults(suiteName: suiteName)

    /// Base URL of the enabled Trailerio addon, shared for the extension to resolve trailers against.
    /// Setting `nil` clears it (Trailerio removed/disabled → extension stops attaching preview videos).
    static var trailerioBaseURL: URL? {
        get {
            guard let string = defaults?.string(forKey: trailerioBaseKey) else { return nil }
            return URL(string: string)
        }
        set {
            guard let defaults else { return }
            if let newValue {
                defaults.set(newValue.absoluteString, forKey: trailerioBaseKey)
            } else {
                defaults.removeObject(forKey: trailerioBaseKey)
            }
        }
    }
}
