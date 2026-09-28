import SwiftUI

/// Shown over the backdrop when no addon could load the title.
struct DetailLoadFailedView: View {
    let title: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Load \(title)", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Check your connection and try again.")
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
        }
    }
}
