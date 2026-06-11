import SwiftUI

/// A compact Stremio-style availability pill for a debrid-backed stream: a green ⚡ tag for a
/// cached (instant) stream, an amber download tag for one that must be fetched into the debrid
/// first. Mirrors the picker's quality-badge styling (tinted capsule + hairline stroke) so it
/// reads as part of the same surface.
struct DebridBadge: View {
    let info: DebridInfo

    /// Cached = instantly playable (green); download = must be fetched first (amber). Exposed so
    /// the detail panel can color its availability row from the same source of truth.
    static let cachedColor = Color(hue: 0.36, saturation: 0.62, brightness: 0.82)
    static let downloadColor = Color(hue: 0.09, saturation: 0.85, brightness: 0.97)

    var body: some View {
        let color = info.isCached ? Self.cachedColor : Self.downloadColor
        HStack(spacing: 5) {
            Image(systemName: info.isCached ? "bolt.fill" : "arrow.down.circle.fill")
            Text(info.code)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.18)))
        .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
        .accessibilityLabel("\(info.service), \(info.isCached ? "cached, instant" : "download required")")
    }
}
