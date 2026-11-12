import CoreGraphics

/// The playing video's picture, as the engine reports it.
struct VideoFormat: Equatable, Sendable {
    enum DynamicRange: Sendable {
        case sdr
        case hdr10
        case hlg
        case dolbyVision
    }

    var size: CGSize
    var dynamicRange: DynamicRange
}
