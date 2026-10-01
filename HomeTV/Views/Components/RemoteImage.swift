import SwiftUI

/// Drop-in replacement for `AsyncImage` backed by `ImageLoader` (downsampled + cached decode).
///
/// Callers pass the point size of the frame they'll render into; the image is decoded to exactly
/// that size off the main thread. The decode is not tied to view lifetime — scrolling away and back
/// is an instant cache hit rather than a re-download.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    /// `.template` draws the image's shape in the foreground style (a white wordmark).
    var renderingMode: Image.TemplateRenderingMode? = nil
    /// Crops transparent margins, for logos on a padded canvas.
    var trimsTransparency = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: ContentMode = .fill,
        renderingMode: Image.TemplateRenderingMode? = nil,
        trimsTransparency: Bool = false,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.renderingMode = renderingMode
        self.trimsTransparency = trimsTransparency
        self.placeholder = placeholder
        // Seed synchronously from the decoded-image cache so an already-loaded image (e.g. a
        // prefetched hero backdrop) is shown on the FIRST frame — no placeholder gap. This is what
        // lets the backdrop slide in already rendered instead of popping in after the slide.
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cachedImage(for: $0, targetSize: targetSize, trimsTransparency: trimsTransparency) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(renderingMode)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: taskID) { await load() }
    }

    private var taskID: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)|\(Int(targetSize.width))x\(Int(targetSize.height))|\(trimsTransparency)"
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        // Don't clear first — keep showing the seeded/previous image until the new one is ready, so
        // there's no flash mid-slide.
        if let loaded = try? await ImageLoader.shared.image(for: url, targetSize: targetSize, trimsTransparency: trimsTransparency) {
            image = loaded
        }
    }
}

extension RemoteImage where Placeholder == Color {
    /// Convenience initializer with a neutral placeholder for the common case.
    init(url: URL?, targetSize: CGSize, contentMode: ContentMode = .fill) {
        self.init(url: url, targetSize: targetSize, contentMode: contentMode) {
            Color(white: 0.12)
        }
    }
}
