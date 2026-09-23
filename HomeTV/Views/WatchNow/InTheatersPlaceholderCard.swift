import SwiftUI

/// A showcase card's slot while the row's source is still answering. It holds the row's full height
/// from the first frame, so the catalog rows below never jump when the real cards land — the same job
/// `ContentRow`'s placeholder row does for a catalog.
struct InTheatersPlaceholderCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(.black.opacity(0.06))
            .frame(width: Theme.Card.showcaseSize.width, height: Theme.Card.showcaseSize.height)
    }
}
