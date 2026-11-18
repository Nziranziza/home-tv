import CoreGraphics
import Foundation
@testable import HomeTV

/// A thumbnailer with no pictures.
struct StubThumbnailer: PlaybackThumbnailer {
    func frame(at time: TimeInterval, maxPixelWidth: Int) async -> CGImage? { nil }
    func close() {}
}
