import CoreGraphics
import SwiftUI

/// A channel's panel colour, sampled from its logo at runtime rather than bundled.
struct BrandColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// Keeps the white wordmark legible on the panel, and a black logo's panel from reading as a hole.
    static let brightnessRange: ClosedRange<Double> = 0.16...0.55

    /// Used when an addon has no logo, or its logo is too transparent to sample.
    static let neutral = BrandColor(red: 0.2, green: 0.2, blue: 0.21)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Alpha-weighted mean of the image's pixels, or nil when it is nearly all transparent.
    init?(averaging image: CGImage) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        let alpha = Double(pixel[3]) / 255
        guard drawn, alpha > 0.05 else { return nil }
        // Premultiplied, so dividing by alpha recovers the mean colour of the opaque pixels.
        self.init(
            red: min(Double(pixel[0]) / 255 / alpha, 1),
            green: min(Double(pixel[1]) / 255 / alpha, 1),
            blue: min(Double(pixel[2]) / 255 / alpha, 1)
        )
    }

    /// The sample with its brightness clamped into `brightnessRange`, hue kept.
    var panel: BrandColor {
        let brightness = max(red, green, blue)
        guard brightness > 0 else {
            let floor = Self.brightnessRange.lowerBound
            return BrandColor(red: floor, green: floor, blue: floor)
        }
        let target = min(max(brightness, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
        let scale = target / brightness
        return BrandColor(red: red * scale, green: green * scale, blue: blue * scale)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
}
