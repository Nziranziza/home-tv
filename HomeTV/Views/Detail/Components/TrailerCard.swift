import SwiftUI

// MARK: - Trailer card

/// A real TMDB trailer: the video's YouTube thumbnail with the trailer name + a play glyph over a
/// bottom gradient. Matches the placeholder card's geometry so the row looks identical either way.
struct TrailerCard: View {
    let trailer: Trailer
    let action: () -> Void

    private var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(trailer.youTubeKey)/hqdefault.jpg")
    }

    var body: some View {
        Button(action: action) {
            RemoteImage(url: thumbnailURL, targetSize: CGSize(width: 426, height: 270), contentMode: .fill) {
                Color(white: 0.08)
            }
            .frame(width: 426, height: 270)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(trailer.title)
                        .font(.system(size: 22, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 13)
            }
            .frame(width: 426, height: 270)
        }
        .buttonStyle(.card)
    }
}

