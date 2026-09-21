import SwiftUI

/// The suggestion strip that sits between the native keyboard and the results. Terms come from the
/// titles and cast names the current query already returned (see `SearchSuggestions`); picking one
/// replaces the query and re-runs the search.
struct SearchSuggestionRow: View {
    let suggestions: [String]
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Search.chipSpacing) {
                ForEach(suggestions, id: \.self) { term in
                    SearchSuggestionChip(term: term) { onSelect(term) }
                }
            }
            .padding(.horizontal, Theme.Row.contentInset)
            .padding(.vertical, Theme.Search.chipRowPadding)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .focusSection()
    }
}
