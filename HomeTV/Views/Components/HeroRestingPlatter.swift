import SwiftUI

/// An unfocused hero button's platter, sampled from the Apple TV reference: black at 50% over the
/// art, edged with a 1pt white hairline at 12%.
struct HeroRestingPlatter<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.black.opacity(0.5))
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}
