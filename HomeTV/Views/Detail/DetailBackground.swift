import SwiftUI

/// The fixed, full-bleed page backdrop. Two stacked layers crossfading on the `p` clock:
///  • Layer 2 (beneath, always present): the still, heavily Gaussian-blurred and dimmed — State B.
///  • Layer 1 (sharp hero) fades out as `p → 1` (`opacity = 1 - p`), carrying the State-A scrims.
///
/// Each layer is its own view that depends only on the backdrop URL, so the expensive blur is
/// computed once (its body is skipped while only the sibling's `opacity` animates on scroll).
struct DetailBackground: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState

    var body: some View {
        ZStack {
            DetailBackdropBlurredLayer(url: model.vm.backdropURL)
            DetailBackdropSharpLayer(url: model.vm.backdropURL)
                .opacity(1 - scroll.p)
        }
        .ignoresSafeArea()
    }
}

/// Full-bleed backdrop image (GeometryReader gives a definite full-screen frame so it covers behind
/// the hero and the content below it).
private struct DetailBackdropImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            RemoteImage(
                url: url,
                targetSize: Theme.Hero.backdropTargetSize,
                contentMode: .fill
            ) {
                Color(white: 0.05)
            }
            .scaledToFill()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.05) // small over-scale so the blur never softens a visible edge
            .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct DetailBackdropBlurredLayer: View {
    let url: URL?

    var body: some View {
        DetailBackdropImage(url: url)
            .blur(radius: 175)                                // very heavy wash — figures fully indistinct
            .saturation(1.05)                                 // keep/boost the warm tint (don't go neutral grey)
            .overlay(Color.black.opacity(0.16))               // ~lum 125 warm (reference target)
            .overlay(
                RadialGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    center: .center, startRadius: 220, endRadius: 1180
                )
                .allowsHitTesting(false)
            )
    }
}

private struct DetailBackdropSharpLayer: View {
    let url: URL?

    var body: some View {
        DetailBackdropImage(url: url)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.78), location: 0.0),
                        .init(color: .clear, location: 0.40)   // transparent by x ≈ 700/1920
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .allowsHitTesting(false)
            )
            .overlay(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
    }
}
