import SwiftUI

/// The catalog's loading and error states.
struct PlayerTestStatusView: View {
    let symbol: String?
    let title: String
    let message: String?
    let retry: (() -> Void)?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    ProgressView()
                }
                Text(title).font(.headline)
            }
            .foregroundStyle(theme.primaryText)
            if let message {
                Text(message).font(.callout).foregroundStyle(theme.secondaryText)
            }
            if let retry {
                Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
