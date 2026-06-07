import SwiftUI

struct SearchView: View {
    @State private var registry = AddonRegistry.shared
    @State private var query: String = ""
    @State private var results: [MetaPreview] = []
    @State private var status: LoadStatus = .idle
    @State private var selection: MetaPreview?

    enum LoadStatus { case idle, loading, loaded, empty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies, series…")
            .task(id: query) {
                await runSearch()
            }
            .metaDetailDestinations(selection: $selection)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle:
            placeholder(icon: "magnifyingglass", message: "Start typing to search across your addons.")
        case .loading:
            ProgressView().controlSize(.large)
        case .empty:
            placeholder(icon: "questionmark.circle", message: "No results for \"\(query)\".")
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 260), spacing: 36)], spacing: 48) {
                ForEach(results) { meta in
                    ContentCard(meta: meta) { selection = meta }
                }
            }
            .padding(60)
        }
    }

    private func placeholder(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
            Text(message)
                .font(.title3)
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            status = .idle
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        if trimmed != query.trimmingCharacters(in: .whitespaces) { return }

        status = .loading

        let searchableCatalogs = registry.enabledAddons.flatMap { addon -> [(InstalledAddon, CatalogDescriptor)] in
            (addon.manifest.catalogs ?? [])
                .filter { catalog in
                    catalog.extra?.contains(where: { $0.name == "search" }) ?? false
                }
                .map { (addon, $0) }
        }

        let collected = await withTaskGroup(of: [MetaPreview].self) { group in
            for (addon, catalog) in searchableCatalogs {
                group.addTask {
                    do {
                        let resp = try await StremioClient.shared.catalog(
                            baseURL: addon.baseURL,
                            type: catalog.type,
                            id: catalog.id,
                            extra: ["search": trimmed]
                        )
                        return resp.metas
                    } catch {
                        return []
                    }
                }
            }
            var all: [MetaPreview] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }

        var seen: Set<String> = []
        results = collected.filter { seen.insert($0.id).inserted }
        status = results.isEmpty ? .empty : .loaded
    }
}
