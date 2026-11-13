import SwiftUI

extension View {
    /// Presents the in-app player at `site`. A new request swaps the screen inside the open cover, so
    /// Continue Watching changes title without the cover closing and reopening.
    func playerCover(at site: PlayerPresenter.Site, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(PlayerCoverModifier(site: site, onDismiss: onDismiss))
    }
}

private struct PlayerCoverModifier: ViewModifier {
    let site: PlayerPresenter.Site
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        let presenter = PlayerPresenter.shared
        // Read here, not in the binding, so a change re-renders the presenter.
        let isPresented = presenter.request(at: site) != nil
        content.fullScreenCover(
            isPresented: Binding(get: { isPresented }, set: { if !$0 { presenter.request = nil } }),
            onDismiss: onDismiss
        ) {
            PlayerCoverContent(site: site)
        }
    }
}

/// The cover's player, rebuilt per request. Holds the last one through the dismissal.
private struct PlayerCoverContent: View {
    let site: PlayerPresenter.Site
    @State private var shown: PlayerRequest?

    init(site: PlayerPresenter.Site) {
        self.site = site
        _shown = State(initialValue: PlayerPresenter.shared.request(at: site))
    }

    var body: some View {
        let request = PlayerPresenter.shared.request(at: site)
        if let current = request ?? shown {
            PlayerScreen(request: current)
                .id(current.id)
                .onChange(of: request?.id) {
                    if let request { shown = request }
                }
        }
    }
}
