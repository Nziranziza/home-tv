import SwiftUI

/// The row preview's peeking thumbnails: a series' episodes from the up-next one, or a movie's related
/// titles. A glimpse of the detail screen's first row, not a control: Down opens that screen.
struct RowPreviewStrip: View {
    let detail: MetaDetailModel

    /// Four in view and the fifth at the card's edge, as in the sample.
    private static let count = 5

    /// Episodes for a series; related titles only for a movie.
    static func hasContent(_ detail: MetaDetailModel) -> Bool {
        !detail.sortedEpisodes.isEmpty || (detail.typeID == "movie" && !detail.vm.relatedItems.isEmpty)
    }

    var body: some View {
        let episodes = self.episodes
        // An overlay on a peek-high base: the row is wider and taller than the card, and must not size
        // the overlay. Only its top shows; the rest runs past the card's edges, where the overlay clips it.
        Color.clear
            .frame(height: Theme.RowPreview.stripPeek)
            .overlay(alignment: .topLeading) {
                HStack(spacing: Theme.RowPreview.stripSpacing) {
                    if episodes.isEmpty {
                        ForEach(detail.vm.relatedItems.prefix(Self.count)) { item in
                            RowPreviewThumbnail(url: ContentCard.artworkURL(for: item, shape: .landscape))
                        }
                    } else {
                        ForEach(episodes) { episode in
                            let info = detail.episodeInfo[Enrichment.episodeKey(season: episode.season ?? 0, episode: episode.episode ?? 0)]
                            RowPreviewThumbnail(url: info?.stillURL ?? episode.thumbnail.flatMap(URL.init(string:)))
                        }
                    }
                }
                .fixedSize()
            }
            .accessibilityHidden(true)
        // TMDB stills for the seasons in view, as the detail's episode row loads them.
        .task(id: "\(detail.metaID)|\(seasons(of: episodes))") {
            for season in seasons(of: episodes) {
                await detail.loadSeasonEnrichment(season)
            }
        }
    }

    /// From the up-next episode, clamped so a late one still fills the row, as the detail's
    /// episode row scrolled to it does.
    private var episodes: ArraySlice<Video> {
        let all = detail.sortedEpisodes
        let upNext = detail.upNext()
        let upNextIndex = upNext.flatMap { next in next.marksEpisode ? all.firstIndex { $0.id == next.video.id } : nil } ?? 0
        let start = max(0, min(upNextIndex, all.count - (Self.count - 1)))
        return all[start...].prefix(Self.count)
    }

    private func seasons(of episodes: ArraySlice<Video>) -> [Int] {
        Set(episodes.compactMap(\.season)).sorted()
    }
}
