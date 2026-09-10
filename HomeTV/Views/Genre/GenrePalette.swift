import SwiftUI

/// The colour a genre is tinted with: one hue per genre through a single shared duotone recipe, so the
/// row reads as a colour spectrum and an unknown addon-supplied genre gets the same treatment.
enum GenrePalette {
    /// Hue in degrees per known genre, keyed by the lowercased option string, spread around the wheel
    /// so neighbouring tiles stay distinguishable.
    private static let hues: [String: Double] = [
        "family": 332, "kids": 340, "action": 20, "animation": 174, "anime": 174,
        "comedy": 148, "drama": 212, "horror": 36,
        "sci-fi": 254, "science fiction": 254, "sci-fi & fantasy": 254,
        "adventure": 46, "thriller": 352, "crime": 190, "romance": 318,
        "documentary": 96, "mystery": 276, "fantasy": 296, "biography": 14,
        "history": 58, "music": 264, "musical": 270, "sport": 82, "war": 68,
        "western": 8, "reality-tv": 306, "talk-show": 196, "game-show": 50,
        "news": 224, "soap": 340, "short": 120
    ]

    private static let shadowSaturation = 0.85
    private static let shadowBrightness = 0.24
    private static let highlightSaturation = 0.62
    private static let highlightBrightness = 0.90

    static func duotone(for genre: Genre) -> GenreDuotone {
        let hue = hues[genre.id.lowercased()] ?? derivedHue(for: genre.id)
        return GenreDuotone(
            shadow: Color(hue: hue / 360, saturation: shadowSaturation, brightness: shadowBrightness),
            highlight: Color(hue: hue / 360, saturation: highlightSaturation, brightness: highlightBrightness)
        )
    }

    /// Hue for an unknown genre. Hand-rolled FNV-1a rather than `hashValue`, which Swift seeds per
    /// process — the tile would change colour on every launch.
    private static func derivedHue(for id: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        return Double(hash % 360)
    }
}
