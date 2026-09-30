import SwiftUI

/// One 16:9 thumbnail in the row preview's peek, drawn as a resting row card.
struct RowPreviewThumbnail: View {
    let url: URL?

    var body: some View {
        let width = Theme.RowPreview.stripCardWidth
        let size = CGSize(width: width, height: width * 9 / 16)
        RemoteImage(url: url, targetSize: size, contentMode: .fill) {
            Color(white: 0.1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
