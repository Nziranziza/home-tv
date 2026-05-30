import SwiftUI

@main
struct HomeTVApp: App {
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
                .preferredColorScheme(.dark)
        }
    }
}
