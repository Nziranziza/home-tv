import CoreGraphics

/// Where the playing video sits while Up Next is up: a quarter-size picture in the top-right corner.
enum UpNextLayout {
    static let videoScale: CGFloat = 0.25
    /// The corner video grows by this much while focused.
    static let focusedGrowth: CGFloat = 1.08
    static let videoInset = CGSize(width: 80, height: 60)
    /// The corner video's visible corner radius.
    static let videoCornerRadius: CGFloat = 24
    static let videoSize = CGSize(width: 1920 * videoScale, height: 1080 * videoScale)
}
