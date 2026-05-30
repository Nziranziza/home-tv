import SwiftUI

/// A single focusable catalog tile. One type drives all three catalog layouts (poster, landscape,
/// square) — the shape selects geometry and which artwork to show. The poster art carries the title,
/// so no caption is shown; focus reveals the type · genre overlaid on the card (Apple-style), with
/// the subtle `CardFocusStyle` lift.
struct ContentCard: View {
    enum Shape {
        case poster
        case landscape
        case square

        var size: CGSize {
            switch self {
            case .poster: Theme.Card.posterSize
            case .landscape: Theme.Card.landscapeSize
            case .square: CGSize(width: Theme.Card.squareSide, height: Theme.Card.squareSide)
            }
        }

        /// Landscape tiles favor the wide backdrop; poster/square use the poster.
        var prefersBackdrop: Bool { self == .landscape }
    }

    let meta: MetaPreview
    var shape: Shape = .poster
    var action: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            RemoteImage(url: artworkURL, targetSize: shape.size, contentMode: .fill) {
                placeholder
            }
            .frame(width: shape.size.width, height: shape.size.height)
            .clipped()
            .overlay(alignment: .bottom) {
                if focused {
                    focusInfo.transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .focused($focused)
        .frame(width: shape.size.width, height: shape.size.height)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meta.name), \(typeAndGenre)")
        .accessibilityAddTraits(.isButton)
    }

    private var artworkURL: URL? {
        let raw = shape.prefersBackdrop ? (meta.background ?? meta.poster) : meta.poster
        return raw.flatMap(URL.init(string:))
    }

    /// Type · genre shown only while focused (e.g. "TV Show · Comedy"), over a bottom scrim.
    private var focusInfo: some View {
        Text(typeAndGenre)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.0),
                        .init(color: .black.opacity(0.75), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    private var typeAndGenre: String {
        var parts = [typeLabel(meta.type)]
        if let genre = meta.genres?.first, !genre.isEmpty { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "movie": "Movie"
        case "series": "TV Show"
        case "channel": "Channel"
        case "tv": "Live TV"
        default: type.capitalized
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(white: 0.85)
            Text(meta.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(12)
        }
    }
}
