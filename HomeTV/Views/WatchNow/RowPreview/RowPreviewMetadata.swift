import SwiftUI

/// The detail hero's text, action row and credits, plus Info, laid out in the preview card. Display
/// only, as in the sample: the buttons never take focus; Select or Down on the card opens the detail.
struct RowPreviewMetadata: View {
    let detail: MetaDetailModel
    let onPlay: (StreamRequest) -> Void
    let onInfo: () -> Void

    /// Never set: the row is disabled, but its API binds each button to a focus value.
    @FocusState private var focus: DetailHeroAction?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DetailHeroCredits(model: detail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            VStack(alignment: .leading, spacing: Theme.Detail.heroColumnSpacing) {
                // A fresh logo per title: `RemoteImage` keeps its last image while a new URL loads,
                // which would show the previous title's logo over this card.
                VStack(alignment: .leading, spacing: Theme.Detail.heroColumnSpacing) {
                    DetailHeroInfo(model: detail)
                }
                .id(detail.metaID)
                DetailHeroActionRow(
                    model: detail,
                    focus: $focus,
                    focusValue: { $0 },
                    onPlay: onPlay
                ) {
                    HeroCircleButton(icon: "info", accessibilityLabel: "More Info", action: onInfo)
                }
                .disabled(true)
            }
        }
    }
}
