import SwiftUI

/// Menu rows: plain at rest; a white capsule with dark text when focused.
struct PlayerMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlayerMenuRowBody(configuration: configuration)
    }
}
