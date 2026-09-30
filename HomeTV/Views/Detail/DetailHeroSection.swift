import SwiftUI

/// State-A hero: the title/logo, chips, synopsis, facts, and action row bottom-anchored to the
/// lower-left, with the cast/credits floated in the upper-right. Fades and drifts up on the collapse
/// clock (`scroll.heroOpacity` / the parallax offset).
struct DetailHeroSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState
    let trakt: TraktService
    @Binding var streamRequest: StreamRequest?
    var zone: FocusState<DetailZone?>.Binding

    var body: some View {
        // The hero is framed and parallaxed by `DetailHeroStage`, which reads the scroll clock in a child
        // view rather than here — so this body doesn't depend on `scroll.offset` and is not re-evaluated on
        // every scroll tick. That keeps the per-tick rebuild (and the up-next episode scan it triggers,
        // see `DetailHeroActionRow.seriesUpNext`) off the collapse animation.
        DetailHeroStage(scroll: scroll) {
            heroContent
        }
    }

    /// State-A column bottom-anchored to the lower-left, with the cast/credits floated in the
    /// bottom-trailing region. Container (rhythm, gutter, bottom inset, collapse fade, focus section) is
    /// the shared `DetailHeroColumn`, so this hero and the episode hero stay in step. The text, buttons
    /// and credits are shared with the row preview.
    private var heroContent: some View {
        DetailHeroColumn(scroll: scroll) {
            DetailHeroInfo(model: model)
            // Every button reports `zone == .hero` while focused; moving focus down to the content flips
            // the zone and drives the full-viewport scroll.
            DetailHeroActionRow(model: model, focus: zone, focusValue: { _ in .hero }) { request in
                streamRequest = request
            }
        } trailing: {
            DetailHeroCredits(model: model)
        }
    }
}
