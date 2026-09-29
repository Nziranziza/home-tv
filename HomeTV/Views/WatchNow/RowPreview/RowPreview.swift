import SwiftUI

/// What a catalog row hands Watch Now when a card is selected: the row's titles, the picked one, and
/// where its card sits on screen so the gallery can grow out of it.
struct RowPreview {
    let items: [MetaPreview]
    let startIndex: Int
    /// The picked card's frame, in global coordinates.
    let sourceFrame: CGRect
    /// Distance between neighbouring card origins in the row.
    let sourceStep: CGFloat
    /// The row's card shape, so the growing card starts from the same artwork the row shows.
    let sourceShape: ContentCard.Shape
}
