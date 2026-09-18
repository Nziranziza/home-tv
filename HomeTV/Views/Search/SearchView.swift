import SwiftUI

/// Search screen. The keyboard, query header and "Press ⏯ to change keyboards" hint are all the
/// native tvOS `.searchable` UI. Under it sits a suggestion strip, and under that either the live
/// results — split into Top Results, TV Shows, Movies and Cast & Crew — or, with no query, the
/// catalog-backed Browse grid.
struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var selection: MetaPreview?
    @State private var castSelection: CastPerson?

    init() {
        let viewModel = SearchViewModel()
        // Debug/verification hook, in the same family as INITIAL_TAB and INITIAL_DETAIL: open the
        // screen with a query already typed, so the result sections can be reached without driving the
        // on-screen keyboard. Unset in normal use.
        if let query = ProcessInfo.processInfo.environment["INITIAL_SEARCH"] {
            viewModel.query = query
        }
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .searchable(text: $viewModel.query, prompt: "Movies, series…")
                .task(id: viewModel.addonCount) { await viewModel.loadBrowse() }
                .task(id: viewModel.searchInputs) { await viewModel.runSearch() }
                .metaDetailDestinations(selection: $selection)
                .navigationDestination(item: $castSelection) { person in
                    CastView(person: person)
                }
                .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.hasNoAddons {
            ContentUnavailableView(
                "No Addons",
                systemImage: "puzzlepiece.extension",
                description: Text("Add a catalog addon in Settings to browse and search.")
            )
        } else {
            switch viewModel.status {
            case .browsing:
                resultsScroll { SearchBrowseSection(items: viewModel.browseItems) { selection = $0 } }
            case .empty:
                ContentUnavailableView.search(text: viewModel.query)
            case .searching where !viewModel.hasResults:
                // Only the *first* search shows a spinner. Once there are sections on screen they stay
                // up while a longer query runs, so growing the query refreshes the rows in place.
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .searching, .results:
                resultsScroll {
                    VStack(alignment: .leading, spacing: Theme.Search.sectionSpacing) {
                        // The chips lead the scroll content rather than being pinned under the
                        // keyboard: the native `.searchable` header scrolls away as focus moves down,
                        // and a pinned row would be left floating over the results.
                        if viewModel.showsSuggestions {
                            SearchSuggestionRow(suggestions: viewModel.suggestions) {
                                viewModel.apply(suggestion: $0)
                            }
                        }
                        SearchResultsSections(
                            viewModel: viewModel, selection: $selection, castSelection: $castSelection
                        )
                    }
                }
            }
        }
    }

    /// The shared page scroll: edge-to-edge horizontally (each section applies its own `contentInset`,
    /// matching Watch Now) with the vertical safe area kept so content clears the tab bar. Deliberately
    /// left clipping — each row disables its own clip for the focus lift, and letting the page scroll
    /// draw outside its bounds is what put the content over the search header.
    private func resultsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.bottom, Theme.WatchNow.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .pageHorizontalInsets()
    }
}

#Preview {
    SearchView()
}
