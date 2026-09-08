import SwiftUI

/// Trailers row. Prefers the Trailerio in-app trailer (a single card that plays full-screen in-app, no
/// YouTube hand-off) when the addon is installed; otherwise falls back to the TMDB YouTube trailers,
/// and finally to the single placeholder card so the row — the top content row for movies — is never
/// empty (the collapse relies on it).
struct DetailTrailersSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    /// The inline hero player. Read only for the loaded trailer's real runtime — it plays the same
    /// source the card presents, so its duration is the card's duration, for free.
    let trailer: TrailerPlaybackController
    /// Set to present the full-screen in-app trailer player (Trailerio path).
    @Binding var trailerRequest: TrailerPlaybackRequest?
    var zone: FocusState<DetailZone?>.Binding
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Trailers", scroll: scroll)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 28) {
                    if !model.trailerCandidates.isEmpty {
                        // Trailerio: one in-app-playable card (the title's trailer). Movies have no
                        // episodes, so Trailers is the top content row.
                        TrailerPlaceholderCard(model: model, duration: trailer.duration) { playInApp() }
                            .contentZone(model.seasons.isEmpty, zone)
                    } else if let trailers = model.enrichment?.trailers, !trailers.isEmpty {
                        ForEach(trailers) { trailer in
                            TrailerCard(trailer: trailer) { openTrailer(trailer) }
                                .contentZone(model.seasons.isEmpty, zone)
                        }
                    } else {
                        TrailerPlaceholderCard(model: model)
                            .contentZone(model.seasons.isEmpty, zone)
                    }
                }
                .padding(.horizontal, Theme.Detail.leftInset)
                .padding(.vertical, 12)
            }
            .detailRowScroll()
            .focusSection()
        }
    }

    /// Play the title's trailer in-app, full-screen (Trailerio sources). Starts from the source the hero
    /// is playing, so the full-screen clip is the one the card previewed (and whose duration it shows);
    /// falls back to the title's full list when the hero has nothing loaded.
    private func playInApp() {
        let order = trailer.playbackOrder
        trailerRequest = TrailerPlaybackRequest(
            title: model.meta?.name ?? model.fallbackTitle,
            candidates: order.isEmpty ? model.trailerCandidates : order
        )
    }

    /// Fallback when Trailerio isn't installed: hand a TMDB trailer off to the YouTube app. There is no
    /// public in-app YouTube playback on tvOS, so this is a best-effort deep link (a no-op if YouTube
    /// isn't installed to claim the scheme).
    private func openTrailer(_ trailer: Trailer) {
        guard let url = URL(string: "youtube://watch?v=\(trailer.youTubeKey)") else { return }
        openURL(url)
    }
}

/// Placeholder shown when TMDB has no real trailers, so the row — the top content row for movies, and
/// the hero-collapse target — is never empty. A focusable `.card` (empty action) on purpose: Down from
/// the hero must land here for a movie, and it mirrors the real `TrailerCard`'s focus lift.
///
/// One full-bleed 426×270 thumbnail (matches the reference's ~452×287 once the .card focus lift scales
/// it). A bottom-anchored dark gradient gives the overlaid text legibility while the image stays
/// faintly visible behind it — NOT an opaque caption bar. Title + "▶ 2m 31s" sit low over the gradient.
private struct TrailerPlaceholderCard: View {
    let model: MetaDetailModel
    /// Real runtime of the trailer this card plays, once the player knows it. The play glyph stands
    /// alone until then (and for the pure placeholder, which has nothing to play), so the label never
    /// shifts the layout as it arrives.
    var duration: Duration?
    /// Selecting the card. Empty for the pure placeholder; plays the in-app trailer for Trailerio.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            RemoteImage(
                url: (model.meta?.background ?? model.meta?.poster).flatMap(URL.init(string:)),
                targetSize: CGSize(width: 426, height: 270),
                contentMode: .fill
            ) {
                Color(white: 0.08)
            }
            .frame(width: 426, height: 270)
            .overlay(alignment: .bottom) {
                // Taller, darker fade so the text reads as clean neutral white/grey over any thumbnail
                // (a weak gradient lets the warm image tint the title); image still shows above the fade.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.meta?.name ?? model.fallbackTitle) Trailer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                        if let duration {
                            Text(duration, format: .units(allowed: [.minutes, .seconds], width: .narrow))
                                .font(.system(size: 19))
                        }
                    }
                    .foregroundStyle(Color(white: 0.67))   // neutral light grey (~RGB 170), not image-tinted
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 13)
            }
            .frame(width: 426, height: 270)
        }
        .buttonStyle(.card)
    }
}
