import CoreGraphics

/// A catalog row's horizontal scroll offset and the range it can scroll through, sampled for its
/// `RowScroller`.
struct RowScrollMetrics: Equatable {
    let offset: CGFloat
    let lower: CGFloat
    let upper: CGFloat
}
