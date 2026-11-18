import SwiftUI

extension View {
    /// Shows an Infuse launch failure from `library`.
    func playerTestLaunchAlert(_ library: PlayerTestLibrary) -> some View {
        modifier(PlayerTestLaunchAlert(library: library))
    }
}

private struct PlayerTestLaunchAlert: ViewModifier {
    @Bindable var library: PlayerTestLibrary

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't Open Infuse",
            isPresented: Binding(
                get: { library.launchError != nil },
                set: { if !$0 { library.launchError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.launchError ?? "")
        }
    }
}
