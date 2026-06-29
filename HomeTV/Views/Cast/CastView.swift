import SwiftUI

/// Shared layout guides for the cast/crew screen.
enum CastLayout {
    /// Left guide for the filmography rows — the same inset the detail screen's rows use.
    static let rowInset: CGFloat = Theme.Detail.leftInset
    /// Gap between the header and the first row, and between rows.
    static let sectionSpacing: CGFloat = 44
    static let headerTopPadding: CGFloat = 80
}

/// The cast/crew (person) screen: a centered header (headshot + name + biography with an inline MORE
/// that expands into a frosted popover) over the person's filmography, grouped into rows — films,
/// crew roles, and TV guest appearances. Reached from a Cast & Crew headshot on the detail screen.
struct CastView: View {
    let person: CastPerson

    @State private var model: CastViewModel
    /// True while the full-bio popover is presented.
    @State private var bioExpanded = false
    /// Set when a filmography card is selected → pushes that title's detail screen.
    @State private var titleSelection: MetaPreview?

    init(person: CastPerson) {
        self.person = person
        _model = State(initialValue: CastViewModel(person: person))
    }

    var body: some View {
        ZStack {
            background

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: CastLayout.sectionSpacing) {
                    CastHeader(name: model.name, biography: model.biography, profileURL: model.profileURL) {
                        withAnimation(.easeOut(duration: 0.22)) { bioExpanded = true }
                    }
                    ForEach(model.sections) { section in
                        CastFilmographyRow(section: section, onSelect: openTitle)
                    }
                }
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .horizontal)
            // While the bio popover is up it owns the focus engine — keep the cast list behind the
            // dimmer unfocusable so the d-pad can't drive hidden rows (notably for a short bio, where
            // the popover has no scrollable target of its own).
            .disabled(bioExpanded)

            if bioExpanded, let biography = model.biography {
                CastBioPopover(name: model.name, biography: biography) {
                    withAnimation(.easeOut(duration: 0.2)) { bioExpanded = false }
                }
                .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await model.load() }
        .navigationDestination(item: $titleSelection) { item in
            MetaDetailView(typeID: item.type, metaID: item.id, fallbackTitle: item.name)
        }
    }

    /// A subtle near-black gradient, brighter toward the top like the reference.
    private var background: some View {
        LinearGradient(
            colors: [Color(white: 0.09), Color(white: 0.03)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// Open a filmography title. Items carry a `TMDBRef`-encoded id (TMDB credits have no IMDB id), so
    /// resolve it to an IMDB id on select before pushing the addon-backed detail screen — the same
    /// bridge the Related row uses.
    private func openTitle(_ item: MetaPreview) {
        guard let ref = TMDBRef(encodedID: item.id) else {
            titleSelection = item
            return
        }
        Task {
            guard let imdb = await TMDBService.shared.imdbID(for: ref) else { return }
            titleSelection = MetaPreview(
                id: imdb, type: item.type, name: item.name,
                poster: item.poster, posterShape: nil, background: item.background,
                logo: nil, description: nil, releaseInfo: nil, imdbRating: nil, genres: nil
            )
        }
    }
}
