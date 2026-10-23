import SwiftUI

/// The transport bar's buttons: dark Liquid Glass at rest; white with a dark label, lifted, when focused.
/// The built-in `.glass` style focuses to grey, not the system player's white. Highlighted, it's lighter
/// glass, for a button whose menu is open.
struct PlayerGlassButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var isHighlighted = false

    func makeBody(configuration: Configuration) -> some View {
        PlayerGlassButton(configuration: configuration, shape: shape, isHighlighted: isHighlighted)
    }
}

extension ButtonStyle where Self == PlayerGlassButtonStyle<Circle> {
    static var playerRound: Self { PlayerGlassButtonStyle(shape: .circle) }

    static func playerRound(isHighlighted: Bool) -> Self {
        PlayerGlassButtonStyle(shape: .circle, isHighlighted: isHighlighted)
    }
}

extension ButtonStyle where Self == PlayerGlassButtonStyle<Capsule> {
    static var playerTab: Self { PlayerGlassButtonStyle(shape: .capsule) }
}
