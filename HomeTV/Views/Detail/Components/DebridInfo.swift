import Foundation

/// The debrid availability a stream was labeled with by its add-on.
///
/// Stremio-style add-ons (Torrentio, Comet, MediaFusion, …) prefix a stream's name with a
/// service tag: a `+` marks a **cached** stream that plays instantly (e.g. `[RD+]`), while
/// `download` marks one that must first be fetched into the debrid (e.g. `[RD download]`).
/// Parsing it once — alongside the rest of `StreamMeta` — lets the picker tell the user, at a
/// glance, which streams are ready to play.
struct DebridInfo: Hashable, Sendable {
    /// Friendly service name, e.g. "Real-Debrid".
    let service: String
    /// Short service code as labeled, e.g. "RD".
    let code: String
    /// True when the add-on marked the stream as already cached (instant), false when it must be
    /// downloaded into the debrid first.
    let isCached: Bool

    /// Finds a `[CODE+]` (cached) or `[CODE download]` (uncached) debrid tag anywhere in `text`.
    static func parse(from text: String) -> DebridInfo? {
        let pattern = /\[\s*([A-Za-z][A-Za-z0-9.\-]{0,9})\s*(\+|download)\s*\]/.ignoresCase()
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let code = String(match.1).uppercased()
        let isCached = match.2.contains("+")
        return DebridInfo(service: name(for: code), code: code, isCached: isCached)
    }

    /// Removes a debrid tag (e.g. `[RD+]`) from a release name so the title reads cleanly.
    static func stripTag(from text: String) -> String {
        let pattern = /\[\s*[A-Za-z][A-Za-z0-9.\-]{0,9}\s*(\+|download)\s*\]/.ignoresCase()
        return text.replacing(pattern, with: "")
    }

    private static func name(for code: String) -> String {
        switch code {
        case "RD": "Real-Debrid"
        case "AD": "AllDebrid"
        case "PM": "Premiumize"
        case "DL": "Debrid-Link"
        case "OC": "Offcloud"
        case "TB": "TorBox"
        case "PP", "PUTIO": "Put.io"
        case "ED": "EasyDebrid"
        default: code
        }
    }
}
