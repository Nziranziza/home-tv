import SwiftUI

/// The result body of the Search screen: Top Results, then TV Shows, Movies and Cast & Crew, each
/// dropped entirely when it has no hits.
struct SearchResultsSections: View {
    let viewModel: SearchViewModel
    @Binding var selection: MetaPreview?
    @Binding var castSelection: CastPerson?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Search.sectionSpacing) {
            if !viewModel.topResults.isEmpty {
                SearchTopResultsSection(items: viewModel.topResults) { selection = $0 }
            }
            if !viewModel.seriesResults.isEmpty {
                SearchPosterSection(title: "TV Shows", items: viewModel.seriesResults) { selection = $0 }
            }
            if !viewModel.movieResults.isEmpty {
                SearchPosterSection(title: "Movies", items: viewModel.movieResults) { selection = $0 }
            }
            if !viewModel.people.isEmpty {
                SearchCastSection(people: viewModel.people) { castSelection = $0 }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
