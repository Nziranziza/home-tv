import CoreGraphics
import Testing
@testable import HomeTV

/// Sampling a channel's panel colour from its logo.
struct BrandColorTests {

    @Test func averagesOpaquePixelsIgnoringTransparentOnes() throws {
        // Left half opaque red, right half transparent: the mean of the opaque pixels is pure red.
        let image = try #require(Self.image(width: 4, height: 4) { x, _ in x < 2 ? (255, 0, 0, 255) : (0, 0, 0, 0) })
        let color = try #require(BrandColor(averaging: image))
        #expect(abs(color.red - 1) < 0.02)
        #expect(color.green < 0.02 && color.blue < 0.02)
    }

    @Test func fullyTransparentLogosAreNotSampled() throws {
        let image = try #require(Self.image(width: 2, height: 2) { _, _ in (0, 0, 0, 0) })
        #expect(BrandColor(averaging: image) == nil)
    }

    @Test func panelDarkensALightSampleAndKeepsItsHue() {
        let panel = BrandColor(red: 1, green: 0.5, blue: 0).panel
        #expect(abs(panel.red - BrandColor.brightnessRange.upperBound) < 0.001)
        #expect(abs(panel.green / panel.red - 0.5) < 0.001)
        #expect(panel.blue == 0)
    }

    @Test func panelLiftsANearBlackSample() {
        let panel = BrandColor(red: 0.02, green: 0.02, blue: 0.04).panel
        #expect(abs(max(panel.red, panel.green, panel.blue) - BrandColor.brightnessRange.lowerBound) < 0.001)
    }

    @Test func panelLeavesAMidToneAlone() {
        let sample = BrandColor(red: 0.3, green: 0.2, blue: 0.1)
        #expect(sample.panel == sample)
    }

    private static func image(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) -> CGImage? {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                bytes += [r, g, b, a]
            }
        }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }
}
