import SwiftUI

/// The metadata pinned over the centred card: title art, description, and Play + Info. One overlay for
/// the whole gallery; only the backdrops slide beneath it.
struct RowPreviewInfoOverlay: View {
    let meta: MetaPreview
    var focus: FocusState<RowPreviewGallery.Control?>.Binding
    let areControlsEnabled: Bool
    let onPlay: () -> Void
    let onInfo: () -> Void
    /// Up from the buttons, back to paging.
    let onExitControls: () -> Void

    /// The logo's decode size, shared with the gallery's prefetch so the reveal is a cache hit.
    static let logoSize = CGSize(width: Theme.Hero.logoMaxWidth, height: Theme.Hero.logoMaxHeight)

    static func logoURL(for meta: MetaPreview) -> URL? {
        meta.logo.flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Hero.contentSpacing) {
            HeroTitleArt(
                logoURL: Self.logoURL(for: meta),
                accessibilityName: meta.name,
                maxWidth: Self.logoSize.width,
                maxHeight: Self.logoSize.height,
                shadow: true
            ) {
                Text(meta.name)
                    .font(Theme.Hero.titleFallbackFont)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
            }
            // A fresh image per title: `RemoteImage` keeps its last image while a new URL loads, which
            // would show the previous title's logo over this card.
            .id(meta.id)
            if let description = meta.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                HeroDescription(text: description)
            }
            HStack(spacing: Theme.Hero.actionRowSpacing) {
                HeroPlayButton(title: "Play", icon: "play.fill", action: onPlay)
                    .focused(focus, equals: .play)
                    .onMoveCommand { if $0 == .up { onExitControls() } }
                HeroCircleButton(icon: "info", accessibilityLabel: "More Info", action: onInfo)
                    .focused(focus, equals: .info)
                    .onMoveCommand { if $0 == .up { onExitControls() } }
            }
            // Keeps Left off Play from escaping to the sidebar.
            .focusBarrier(.leading, isActive: areControlsEnabled, gap: Theme.Hero.focusBarrierWidth) {
                Task { focus.wrappedValue = .play }
            }
            .padding(.leading, -Theme.Hero.focusBarrierWidth)
            .padding(.top, Theme.Hero.actionRowTopPadding)
            .disabled(!areControlsEnabled)
        }
        .padding(.leading, Theme.RowPreview.infoLeading)
        .padding(.bottom, Theme.RowPreview.infoBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.35),
                    .init(color: .black.opacity(0.75), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
