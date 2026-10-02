import SwiftUI

/// A hero credit line such as `Starring A, B, C`: a dim label inline ahead of brighter names, wrapping
/// ragged-right. Shared by the detail hero and the row preview.
struct HeroCreditLine: View {
    let label: String
    let names: [String]

    var body: some View {
        (
            // Both dimmed, the label more so, as Apple TV draws them.
            Text("\(label) ").foregroundStyle(Theme.Color.primaryText.opacity(0.3))
            + Text(names.joined(separator: ", ")).foregroundStyle(Theme.Color.primaryText.opacity(0.5))
        )
        .font(.system(size: 28))
        .multilineTextAlignment(.leading)
        .lineLimit(2)
    }
}
