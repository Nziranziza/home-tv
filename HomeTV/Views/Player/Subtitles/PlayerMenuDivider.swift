import SwiftUI

/// The hairline between a menu's choices and its sub-menus.
struct PlayerMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 19)
            .padding(.top, 18)
            .padding(.bottom, 2)
    }
}
