import MediaAccessibility

/// The system caption styles. Choosing one changes it for every app, as the system player does.
@MainActor
enum CaptionStyles {
    static func all() -> [CaptionStyle] {
        let ids = MACaptionAppearanceCopyProfileIDs() as? [String] ?? []
        return ids.map { CaptionStyle(id: $0, name: MACaptionAppearanceCopyProfileName($0 as CFString) as String) }
    }

    static var activeID: String { MACaptionAppearanceCopyActiveProfileID() as String }

    static func activate(_ id: String) {
        MACaptionAppearanceSetActiveProfileID(id as CFString)
    }
}
