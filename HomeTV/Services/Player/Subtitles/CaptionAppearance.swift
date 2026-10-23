import MediaAccessibility
import SwiftUI

/// How the active caption style draws text, for the Style menu's preview.
struct CaptionAppearance: Equatable {
    enum Edge: Equatable {
        case none
        case raised
        case depressed
        case outline
        case dropShadow
    }

    var foreground: Color
    /// Behind each line's characters.
    var background: Color
    /// The box around the whole caption; Transparent Background keeps a half-opaque one.
    var window: Color
    var windowCornerRadius: CGFloat
    var relativeSize: CGFloat
    var edge: Edge

    @MainActor
    static func active() -> CaptionAppearance {
        CaptionAppearance(
            foreground: color(MACaptionAppearanceCopyForegroundColor(.user, nil).takeRetainedValue(),
                              opacity: MACaptionAppearanceGetForegroundOpacity(.user, nil)),
            background: color(MACaptionAppearanceCopyBackgroundColor(.user, nil).takeRetainedValue(),
                              opacity: MACaptionAppearanceGetBackgroundOpacity(.user, nil)),
            window: color(MACaptionAppearanceCopyWindowColor(.user, nil).takeRetainedValue(),
                          opacity: MACaptionAppearanceGetWindowOpacity(.user, nil)),
            windowCornerRadius: MACaptionAppearanceGetWindowRoundedCornerRadius(.user, nil),
            relativeSize: MACaptionAppearanceGetRelativeCharacterSize(.user, nil),
            edge: edge(MACaptionAppearanceGetTextEdgeStyle(.user, nil))
        )
    }

    private static func color(_ color: CGColor, opacity: CGFloat) -> Color {
        Color(cgColor: color).opacity(opacity)
    }

    private static func edge(_ style: MACaptionAppearanceTextEdgeStyle) -> Edge {
        switch style {
        case .raised: .raised
        case .depressed: .depressed
        case .uniform: .outline
        case .dropShadow: .dropShadow
        default: .none
        }
    }
}
