import SwiftUI

/// The loading screen's title, for titles without a logo.
struct PlayerLoadingTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle)
            .bold()
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }
}
