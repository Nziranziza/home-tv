import SwiftUI

/// The genre screen: a poster grid of one genre's titles, pushed from a Browse by Genre tile.
struct GenreBrowseView: View {
    let genre: Genre
    var onSelect: (MetaPreview) -> Void

    @State private var model: GenreBrowseModel
    @Environment(\.theme) private var theme

    init(genre: Genre, onSelect: @escaping (MetaPreview) -> Void) {
        self.genre = genre
        self.onSelect = onSelect
        _model = State(initialValue: GenreBrowseModel(genre: genre))
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            GenreBrowseContent(genre: genre, status: model.status, items: model.items, onSelect: onSelect)
        }
        .task { await model.load() }
    }
}

/// The genre screen's body for one load state.
private struct GenreBrowseContent: View {
    let genre: Genre
    let status: GenreBrowseModel.Status
    let items: [MetaPreview]
    let onSelect: (MetaPreview) -> Void

    var body: some View {
        switch status {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .loaded:
            PosterGrid(
                title: genre.displayName,
                titleStyle: .screen,
                items: items,
                onSelect: onSelect
            )
            .padding(.vertical, Theme.Spacing.section)
        case .empty:
            ContentUnavailableView(
                genre.displayName,
                systemImage: "film.stack",
                description: Text("No titles in this genre from your installed addons.")
            )
        case .failed:
            ContentUnavailableView(
                "Couldn’t Load \(genre.displayName)",
                systemImage: "exclamationmark.triangle",
                description: Text("Check your connection and try again.")
            )
        }
    }
}
