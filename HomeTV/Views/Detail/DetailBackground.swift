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
    /// The inline hero trailer (Trailerio). Renders over the sharp still and crossfades with it.
    let trailer: TrailerPlaybackController

    var body: some View {
        ZStack {
            DetailBackdropBlurredLayer(url: model.vm.backdropURL)
            DetailBackdropSharpLayer(url: model.vm.backdropURL)
                .opacity(1 - scroll.p)
            DetailHeroTrailerLayer(controller: trailer, scroll: scroll)
        }
        .ignoresSafeArea()
    }
}

/// The fixed page backdrop for the single-episode detail screen: the same crossfading sharp→blurred
/// treatment as the title detail (sharp behind the hero, blurred behind the content, ramped on the
/// collapse clock), but keyed off a single still URL and with no inline trailer layer — the episode
/// hero shows its still, not an autoplaying trailer.
struct EpisodeBackground: View {
    let url: URL?
    let scroll: DetailScrollState

    var body: some View {
        ZStack {
            DetailBackdropBlurredLayer(url: url)
            DetailBackdropSharpLayer(url: url)
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
        DetailBackdropBlurredImage(url: url)              // low-res decode + small blur, upscaled (see below)
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

/// The heavily-blurred backdrop wash, produced cheaply. A live `.blur(radius: 175)` over the full-screen
/// image is one of the most expensive GPU passes on tvOS (cost scales with displayed pixels × radius) and
/// hitches every time a detail screen is pushed. Because a Gaussian that heavy obliterates all detail, the
/// source resolution is irrelevant to the result — so we decode + blur at 1/`downscale` size and scale the
/// small blurred raster up to fill. The blur then runs on ~1/64th the pixels with a proportionally smaller
/// radius (visually identical wash), and the decode is a tiny thumbnail instead of a ~33 MB 4K image. The
/// `saturation`/overlays and the fill + 1.05 overscale geometry are unchanged from the old full-res layer.
private struct DetailBackdropBlurredImage: View {
    let url: URL?

    /// Render the wash at 1/8 linear scale (1920→240 pt). The `.blur` radius is divided by the same factor
    /// so the upscaled result matches a full-res `.blur(radius: 175)`.
    private static let downscale: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let smallSize = CGSize(width: geo.size.width / Self.downscale,
                                   height: geo.size.height / Self.downscale)
            RemoteImage(
                url: url,
                targetSize: smallSize,
                contentMode: .fill
            ) {
                Color(white: 0.05)
            }
            .scaledToFill()
            .frame(width: smallSize.width, height: smallSize.height)
            .blur(radius: 175 / Self.downscale)              // ≈ 22 on the small raster ≈ 175 once upscaled
            .scaleEffect(Self.downscale * 1.05)              // upscale to fill + the same 1.05 overscale as the sharp layer
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
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
