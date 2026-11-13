import Foundation

/// Loads the Info tab's title info from the enabled add-ons. Meta is cached by `StremioClient`, so
/// after the detail screen this is usually a warm read.
@MainActor
enum PlayerTitleInfoLoader {
    static func load(type: String, item: PlaybackItem) async -> PlayerTitleInfo? {
        var metas: [Meta] = []
        for addon in AddonRegistry.shared.enabledAddons {
            guard !Task.isCancelled else { return nil }
            guard let meta = try? await StremioClient.shared.meta(
                baseURL: addon.baseURL, type: type, id: item.showID
            ).meta else { continue }
            metas.append(meta)
            if PlayerTitleInfo.isComplete(metas, type: type, item: item) { break }
        }
        return PlayerTitleInfo.merging(metas, type: type, item: item)
    }
}
