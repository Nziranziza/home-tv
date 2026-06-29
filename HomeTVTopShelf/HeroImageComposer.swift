import SwiftUI
import UIKit

/// Builds the carousel hero artwork the way Apple's TV app does: the title's logo treatment laid
/// over its wide background still. The Top Shelf API exposes a single image per item, so we composite
/// the two source images (Cinemeta returns them separately) into one PNG, cache it, and hand the
/// carousel that file URL.
@MainActor
enum HeroImageComposer {
    /// Shared container the system's out-of-process Top Shelf renderer can read. Local image files
    /// MUST live here — files in the extension's private container are invisible to that process,
    /// which renders the carousel blank. Must match the App Group entitlement on both targets.
    nonisolated static let appGroup = "group.com.hometv.HomeTV"

    /// 16:9 canvas matching the carousel's aspect. 1080p kept at 1x scale: an app extension has a
    /// tight memory budget, and a 2x (3840×2160) bitmap per item risks the extension being killed —
    /// which itself blanks the carousel.
    private static let canvas = CGSize(width: 1920, height: 1080)

    /// Downloads the background (and logo, if present), composites them, writes a PNG into the shared
    /// App Group container, and returns its file URL. Returns nil when the background can't be loaded
    /// or the container is unavailable — the caller then falls back to the plain remote artwork.
    ///
    /// Cinemeta artwork is stable for a given title id, so an already-composited file is reused as-is:
    /// every Top Shelf refresh otherwise re-downloads and re-renders artwork that hasn't changed.
    static func makeHero(identifier: String, backgroundURL: URL, logoURL: URL?) async -> URL? {
        guard let destination = containerURL(for: identifier) else { return nil }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard let background = await image(from: backgroundURL) else { return nil }
        var logo: UIImage?
        if let logoURL { logo = await image(from: logoURL) }

        let renderer = ImageRenderer(content: HeroComposite(background: background, logo: logo, size: canvas))
        renderer.scale = 1
        guard let rendered = renderer.uiImage, let data = rendered.pngData() else { return nil }

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            return nil
        }
        return destination
    }

    private static func image(from url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    /// Deletes composited heroes in the shared container that aren't backing a current carousel item.
    /// The popular catalog rotates over time; without this, a hero PNG is left behind for every title
    /// that ever appeared, growing the App Group container without bound.
    nonisolated static func pruneHeroes(keeping identifiers: [String]) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let files = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return
        }
        let keep = Set(identifiers.map(fileName(for:)))
        for file in files where file.pathExtension == "png" && file.lastPathComponent.hasPrefix("hero-") {
            if !keep.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// A stable, filesystem-safe path per title in the shared container so refreshes reuse in place.
    /// Returns nil if the App Group container can't be resolved (entitlement missing).
    private static func containerURL(for identifier: String) -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        return base.appending(path: fileName(for: identifier))
    }

    /// The stable, filesystem-safe file name for a title's composited hero.
    nonisolated private static func fileName(for identifier: String) -> String {
        let safe = identifier.filter { $0.isLetter || $0.isNumber }
        return "hero-\(safe).png"
    }
}

/// The compositing layout: background fills the frame, a top scrim keeps the logo legible over
/// bright art, and the logo sits in the top-leading corner.
private struct HeroComposite: View {
    let background: UIImage
    let logo: UIImage?
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: background)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            if let logo {
                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )

                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: size.width * 0.4, maxHeight: size.height * 0.24, alignment: .topLeading)
                    .padding(.leading, size.width * 0.05)
                    .padding(.top, size.height * 0.07)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
