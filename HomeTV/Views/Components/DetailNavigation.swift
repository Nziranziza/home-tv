import SwiftUI

extension View {
    /// The two-path detail navigation shared by Watch Now, Library, and Search: navigate either by a
    /// bound selected item or by a `MetaPreview` pushed onto the stack. Both resolve to `MetaDetailView`.
    func metaDetailDestinations(selection: Binding<MetaPreview?>) -> some View {
        navigationDestination(item: selection) { meta in
            MetaDetailView(typeID: meta.type, metaID: meta.id, fallbackTitle: meta.name)
        }
        .navigationDestination(for: MetaPreview.self) { meta in
            MetaDetailView(typeID: meta.type, metaID: meta.id, fallbackTitle: meta.name)
        }
    }

    /// Presents the full-screen stream picker for a `StreamRequest`.
    func streamPickerCover(request: Binding<StreamRequest?>) -> some View {
        fullScreenCover(item: request) { req in
            StreamPickerView(
                type: req.type,
                contentID: req.contentID,
                title: req.title,
                backgroundURL: req.backgroundURL,
                logoURL: req.logoURL
            )
        }
    }
}
