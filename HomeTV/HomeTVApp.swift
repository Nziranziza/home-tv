import SwiftUI

@main
struct HomeTVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Shared on-disk cache for image bytes. ImageLoader's URLSession points at this, so artwork
        // survives view churn, tab switches, and relaunches instead of being re-downloaded.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Single source of truth for the app's appearance — light, mirroring Apple TV+.
                // `preferredColorScheme` drives system controls (search keyboard, toggles); the
                // `\.theme` palette drives our own chrome colors. Flip both to add dark mode later.
                .preferredColorScheme(.light)
                .environment(\.theme, .light)
                // If a Trakt session is restored from the Keychain, validate it and warm the
                // watched/watchlist/playback caches so the views have data on first paint.
                .task { await TraktService.shared.bootstrap() }
                // Returning to HomeTV re-syncs the watched/watchlist/playback caches. Playback hands off
                // to an external player (Infuse/VLC), which backgrounds us and scrobbles to Trakt; coming
                // back re-activates the scene, so this is where a title just finished elsewhere becomes
                // watched here — without waiting for a relaunch. `onChange` doesn't fire for the initial
                // `.active` at cold launch, so `bootstrap()` above owns that first sync (no double fetch).
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, TraktService.shared.isSignedIn else { return }
                    Task { await TraktService.shared.refreshLibrary() }
                }
                // Top Shelf posters open hometv:// links; route them to the right detail screen.
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
    }
}
