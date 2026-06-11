import SwiftUI

/// Real TMDB trailers (YouTube) when enriched; otherwise the single placeholder card so the row —
/// which is the top content row for movies — is never empty (the collapse relies on it).
struct DetailTrailersSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    var zone: FocusState<MetaDetailView.Zone?>.Binding
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "Trailers", scroll: scroll)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 28) {
                    if let trailers = model.enrichment?.trailers, !trailers.isEmpty {
                        ForEach(trailers) { trailer in
                            TrailerCard(trailer: trailer) { openTrailer(trailer) }
                                // Movies have no episodes, so Trailers is the top content row.
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

    /// Hand a trailer off to the YouTube app. There is no public in-app YouTube playback on tvOS, so
    /// this is a best-effort deep link (a no-op if YouTube isn't installed to claim the scheme).
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
/// faintly visible behind it — NOT an opaque caption bar. Title + "▶ 1m" sit low over the gradient.
private struct TrailerPlaceholderCard: View {
    let model: MetaDetailModel

    var body: some View {
        Button { } label: {
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
                        Text("1m")   // PLACEHOLDER duration
                            .font(.system(size: 19))
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
