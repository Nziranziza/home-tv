import SwiftUI

/// The search field and a menu per facet, each listing its values with counts.
struct PlayerTestBrowserControls: View {
    let scope: PlayerTestScope
    @Binding var query: PlayerTestQuery

    var body: some View {
        HStack {
            TextField("Search: Dolby Vision, HEVC, Atmos, PGS…", text: $query.text)
                .frame(width: 560)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(scope.facets, id: \.facet) { facet, options in
                        PlayerTestFacetMenu(
                            facet: facet,
                            options: options,
                            selection: Binding(
                                get: { query.facets[facet] },
                                set: { query.facets[facet] = $0 }
                            )
                        )
                    }
                    if !query.isEmpty {
                        Button("Clear", systemImage: "xmark.circle") { query = PlayerTestQuery() }
                    }
                }
                .buttonStyle(.bordered)
                .padding(.vertical, Theme.Spacing.stack)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct PlayerTestFacetMenu: View {
    let facet: PlayerTestFacet
    let options: [PlayerTestFacetOption]
    @Binding var selection: String?

    var body: some View {
        // A menu Picker shows only its value on tvOS, so the label names the facet too.
        Menu {
            Picker(facet.title, selection: $selection) {
                Text("All").tag(String?.none)
                ForEach(options, id: \.value) { option in
                    Text("\(option.title)  \(option.count.formatted())").tag(Optional(option.value))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(facet.title): \(options.first { $0.value == selection }?.title ?? "All")")
        }
    }
}
