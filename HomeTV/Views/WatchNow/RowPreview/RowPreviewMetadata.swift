import SwiftUI

/// The detail hero's text, action row and credits, plus Info, laid out in the preview card.
struct RowPreviewMetadata: View {
    let detail: MetaDetailModel
    var focus: FocusState<RowPreviewGallery.Control?>.Binding
    let areControlsEnabled: Bool
    let onPlay: (StreamRequest) -> Void
    let onInfo: () -> Void
    /// Up from the buttons, back to paging.
    let onExitControls: () -> Void

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
                    focus: focus,
                    focusValue: { .action($0) },
                    onPlay: onPlay,
                    onMoveUp: onExitControls
                ) {
                    HeroCircleButton(icon: "info", accessibilityLabel: "More Info", action: onInfo)
                        .focused(focus, equals: .info)
                        .onMoveCommand { if $0 == .up { onExitControls() } }
                }
                // Keeps Left off Play from escaping to the sidebar.
                .focusBarrier(.leading, isActive: areControlsEnabled, gap: Theme.Hero.focusBarrierWidth) {
                    Task { focus.wrappedValue = .action(.play) }
                }
                .padding(.leading, -Theme.Hero.focusBarrierWidth)
                .disabled(!areControlsEnabled)
            }
        }
    }
}
