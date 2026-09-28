import SwiftUI

/// A Top 10 poster: its rank in the top-left corner and its genre along the bottom, shown whether or
/// not the card is focused.
struct TopTenCard: View {
    let meta: MetaPreview
    let rank: Int
    var action: () -> Void = {}

    private var size: CGSize { Theme.Card.posterSize }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: meta.poster.flatMap(URL.init(string:)), targetSize: size, contentMode: .fill) {
                    ZStack {
                        Color(white: 0.85)
                        Text(meta.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                if let caption {
                    Text(caption)
                        .font(Theme.Channel.topTenCaptionFont)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 14)
                        .background(
                            LinearGradient(
                                colors: [.black.opacity(0), .black.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                Text(rank, format: .number)
                    .font(Theme.Channel.rankFont)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .padding(Theme.Channel.rankInsets)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(rank). \(meta.name)\(caption.map { ", \($0)" } ?? "")")
    }

    private var caption: String? { meta.genres?.splitGenres().first }
}
