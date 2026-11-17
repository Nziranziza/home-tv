import SwiftUI

/// Up Next's lower left: the show's logo, the next episode's line, and Next Episode with its countdown.
struct UpNextDetails: View {
    let model: PlayerModel
    let episode: UpNextEpisode
    let focus: FocusState<PlayerFocus?>.Binding

    private static let logoSize = CGSize(width: 420, height: 120)

    var body: some View {
        // Gaps measured against the system player's Up Next.
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.bottom, 32)
            Text(episode.label)
                .font(.caption)
                .lineLimit(1)
                .padding(.bottom, 12)
            Button(action: model.playUpNext) {
                // Tight, as in the system player; the default spacing leaves a wide gap on tvOS.
                HStack(spacing: 12) {
                    UpNextCountdownRing(model: model)
                    Text("Next Episode")
                        .font(.body)
                        .bold()
                        .lineLimit(1)
                }
                .padding(.leading, 18)
                .padding(.trailing, 30)
                .padding(.vertical, 10)
            }
            .buttonStyle(.playerTab)
            // Hugs its label rather than taking the logo's width.
            .fixedSize()
            .focused(focus, equals: .upNextNextEpisode)
            // The corner video is far up and to the right, out of the focus engine's reach.
            .onMoveCommand { direction in
                if direction == .up || direction == .right { focus.wrappedValue = .upNextVideo }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var logo: some View {
        let title = Text(episode.request.title).font(.title2).bold()
        if let logoURL = episode.request.logoURL {
            RemoteImage(url: logoURL, targetSize: Self.logoSize, contentMode: .fit, trimsTransparency: true) {
                title
            }
            .frame(maxWidth: Self.logoSize.width, maxHeight: Self.logoSize.height, alignment: .bottomLeading)
            .accessibilityLabel(episode.request.title)
        } else {
            title
        }
    }
}
