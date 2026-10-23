import SwiftUI

/// A caption edge style as SwiftUI shadows. An outline is approximated with tight stacked shadows.
struct CaptionEdgeShadow {
    let edge: CaptionAppearance.Edge

    var color: Color {
        switch edge {
        case .none: .clear
        case .outline: .black
        case .raised, .depressed, .dropShadow: .black.opacity(0.8)
        }
    }

    var radius: CGFloat {
        switch edge {
        case .dropShadow: 3
        case .outline: 1
        case .none, .raised, .depressed: 0
        }
    }

    var offset: CGSize {
        switch edge {
        case .raised: CGSize(width: 0, height: 2)
        case .depressed: CGSize(width: 0, height: -2)
        case .dropShadow: CGSize(width: 2, height: 2)
        case .none, .outline: .zero
        }
    }

    /// Extra passes that thicken an outline.
    var outlineColor: Color { edge == .outline ? .black : .clear }
}
