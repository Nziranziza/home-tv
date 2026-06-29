import SwiftUI

extension View {
    /// Pushes a `MetaPreview` value (from a `NavigationLink(value:)` or a path append) onto the stack
    /// as a `MetaDetailView`. The building block both detail-navigation entry points resolve to.
    ///
    /// `.id(meta.id)` ties the view's identity to the title: when a deep link replaces the stack's top
    /// (e.g. swapping one detail for another via the navigation path) SwiftUI would otherwise reuse the
    /// existing `MetaDetailView` at that depth, keeping its `@State` model bound to the old title. The
    /// id forces a fresh view (and a fresh load) for a different title.
    func metaDetailDestination() -> some View {
        navigationDestination(for: MetaPreview.self) { meta in
            MetaDetailView(typeID: meta.type, metaID: meta.id, fallbackTitle: meta.name)
                .id(meta.id)
        }
    }

    /// The two-path detail navigation shared by Library and Search: navigate either by a bound
    /// selected item or by a `MetaPreview` pushed onto the stack. Both resolve to `MetaDetailView`.
    func metaDetailDestinations(selection: Binding<MetaPreview?>) -> some View {
        navigationDestination(item: selection) { meta in
            MetaDetailView(typeID: meta.type, metaID: meta.id, fallbackTitle: meta.name)
                .id(meta.id)
        }
        .metaDetailDestination()
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
