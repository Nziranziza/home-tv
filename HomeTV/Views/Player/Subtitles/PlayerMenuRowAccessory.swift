import SwiftUI

/// A menu row's chevron or gear, set in from the capsule's end as the system player does.
struct PlayerMenuRowAccessory: View {
    let accessory: PlayerMenuAccessory

    var body: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .padding(.trailing, 20)
        case .gear:
            Image(systemName: "gearshape")
                .padding(.trailing, 28)
        }
    }
}
