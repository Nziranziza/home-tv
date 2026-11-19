import SwiftUI

/// A grey heading between a menu's sections, set like the panel's own title.
struct PlayerMenuSectionHeader: View {
    let title: String

    static let height: CGFloat = 67

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 36 - PlayerMenuMetrics.rowInset)
            .padding(.bottom, 13.5)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .bottomLeading)
    }
}
