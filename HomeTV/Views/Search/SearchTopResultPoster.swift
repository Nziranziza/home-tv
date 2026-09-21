import SwiftUI

/// The small poster on a Top Results card. Falls back to a plain rounded fill while the artwork
/// loads, or when the hit carries no poster at all.
struct SearchTopResultPoster: View {
    let posterPath: String?

    @Environment(\.theme) private var theme

    var body: some View {
        RemoteImage(url: posterPath.flatMap(URL.init(string:)),
                    targetSize: Theme.Search.topResultPosterSize, contentMode: .fill) {
            RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                .fill(theme.cardRest)
        }
        .frame(width: Theme.Search.topResultPosterSize.width,
               height: Theme.Search.topResultPosterSize.height)
        .clipShape(.rect(cornerRadius: Theme.Radius.badge))
    }
}
