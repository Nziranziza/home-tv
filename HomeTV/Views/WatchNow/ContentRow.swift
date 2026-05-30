import SwiftUI

struct ContentRowSpec: Identifiable, Hashable {
    let addon: InstalledAddon
    let catalog: CatalogDescriptor

    var id: String { "\(addon.id)::\(catalog.type)::\(catalog.id)" }

    /// Catalog name with the content type folded in, Apple-style ("Popular Movies" / "Popular TV
    /// Shows"), so movie and series catalogs that share a name (e.g. Cinemeta's "Popular") are
    /// distinguishable. Skips appending if the name already mentions the type.
    var title: String {
        let base = catalog.name ?? catalog.id.capitalized
        guard let typeWord = Self.typeWord(catalog.type),
              !base.localizedCaseInsensitiveContains(typeWord) else { return base }
        return "\(base) \(typeWord)"
    }

    private static func typeWord(_ type: String) -> String? {
        switch type {
        case "movie": "Movies"
        case "series": "TV Shows"
        case "channel": "Channels"
        default: nil
        }
    }
}

struct ContentRow: View {
    let spec: ContentRowSpec
    var onSelect: (MetaPreview) -> Void = { _ in }

    @State private var metas: [MetaPreview] = []
    @State private var status: LoadStatus = .idle

    enum LoadStatus { case idle, loading, loaded, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: spec.title)
            switch status {
            case .loading, .idle:
                placeholderRow
            case .failed where metas.isEmpty:
                EmptyView()
            case .loaded, .failed:
                postersRow
            }
        }
        // Treat the whole row as one vertical focus target so Up/Down between rows works no matter
        // how far this row is scrolled horizontally.
        .focusSection()
        .task(id: spec.id) { await load() }
    }

    private var rowShape: RowShape {
        let first = metas.first?.posterShape?.lowercased()
        return RowShape(rawValue: first ?? "") ?? .poster
    }

    private var isLandscape: Bool { rowShape == .landscape }

    @ViewBuilder
    private var postersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: isLandscape ? Theme.Row.landscapeCardSpacing : Theme.Row.posterCardSpacing) {
                ForEach(metas) { meta in
                    ContentCard(meta: meta, shape: rowShape.cardShape) { onSelect(meta) }
                }
            }
            .padding(.horizontal, Theme.Row.contentInset)
            .padding(.vertical, isLandscape ? Theme.Row.landscapeVerticalPadding : Theme.Row.posterVerticalPadding)
            
        }
        .frame(height: isLandscape ? Theme.Row.landscapeHeight : Theme.Row.posterHeight)
        .scrollClipDisabled()
    }

    private var placeholderRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Row.posterCardSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .fill(.black.opacity(0.06))
                        .frame(width: Theme.Card.posterSize.width, height: Theme.Card.posterSize.height)
                }
            }
            .padding(.horizontal, Theme.Row.contentInset)
            .padding(.vertical, Theme.Row.posterVerticalPadding)
        }
        .frame(height: Theme.Row.posterHeight)
        .redacted(reason: .placeholder)
        .scrollClipDisabled()
    }

    private func load() async {
        guard status == .idle else { return }
        status = .loading
        do {
            let response = try await StremioClient.shared.catalog(
                baseURL: spec.addon.baseURL,
                type: spec.catalog.type,
                id: spec.catalog.id
            )
            metas = response.metas
            status = .loaded
        } catch {
            status = .failed
        }
    }

    enum RowShape: String {
        case poster
        case landscape
        case square

        var cardShape: ContentCard.Shape {
            switch self {
            case .poster: .poster
            case .landscape: .landscape
            case .square: .square
            }
        }
    }
}
