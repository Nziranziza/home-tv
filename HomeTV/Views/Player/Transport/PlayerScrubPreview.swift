import SwiftUI

/// The scrub thumbnail: a dark frame until a picture arrives.
struct PlayerScrubPreview: View {
    let image: CGImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: 0.04))
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
    }
}
