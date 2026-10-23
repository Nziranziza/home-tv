import SwiftUI

/// The player's full-screen button: no focus lift or highlight, so the video stays untouched.
struct PlayerSurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
