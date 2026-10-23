import CoreGraphics

/// The menu panel's sizes, measured against the system player.
enum PlayerMenuMetrics {
    static let width: CGFloat = 450
    /// Rows sit this far in from the panel's sides.
    static let rowInset: CGFloat = 17
    /// Above the first row, so its focused capsule isn't clipped.
    static let topPadding: CGFloat = 3.5
    /// Under the last row; room for its focused capsule too.
    static let bottomPadding: CGFloat = 16
}
