import SwiftUI

/// The transport bar's buttons: dark Liquid Glass at rest; white with a dark label, lifted, when focused.
/// The built-in `.glass` style focuses to grey, not the system player's white.
struct PlayerGlassButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        PlayerGlassButton(configuration: configuration, shape: shape)
    }
}

extension ButtonStyle where Self == PlayerGlassButtonStyle<Circle> {
    static var playerRound: Self { PlayerGlassButtonStyle(shape: .circle) }
}

extension ButtonStyle where Self == PlayerGlassButtonStyle<Capsule> {
    static var playerTab: Self { PlayerGlassButtonStyle(shape: .capsule) }
}
