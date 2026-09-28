import Foundation
import Testing
@testable import HomeTV

/// When the detail page reveals its content, and which art it paints before the meta loads.
@MainActor
struct DetailReadinessTests {
    @Test func staysHiddenUntilTheMetaLoads() {
        let readiness = DetailReadiness(metaLoaded: false, enrichmentSettled: true, capElapsed: true)
        #expect(!readiness.isReady)
    }

    @Test func waitsOnEnrichmentOnceTheMetaLoads() {
        #expect(!DetailReadiness(metaLoaded: true).isReady)
    }

    @Test func revealsWhenEnrichmentSettles() {
        #expect(DetailReadiness(metaLoaded: true, enrichmentSettled: true).isReady)
    }

    @Test func theCapRevealsWithoutEnrichment() {
        #expect(DetailReadiness(metaLoaded: true, capElapsed: true).isReady)
    }

    @Test func thePreviewPathIsReadyAfterLoad() async {
        let model = MetaDetailModel(
            typeID: "movie", metaID: "tt1", fallbackTitle: "Sample", previewMeta: meta(background: nil)
        )
        #expect(!model.isContentReady)
        await model.load()
        #expect(model.isContentReady)
    }

    @Test func theSeedBackdropShowsBeforeTheMetaLoads() {
        let vm = viewModel(meta: nil, seed: seed(background: "https://x/seed.jpg"))
        #expect(vm.backdropURL == URL(string: "https://x/seed.jpg"))
    }

    @Test func theSeedBackdropIsKeptOnceTheMetaLoads() {
        let vm = viewModel(meta: meta(background: "https://x/meta.jpg"), seed: seed(background: "https://x/seed.jpg"))
        #expect(vm.backdropURL == URL(string: "https://x/seed.jpg"))
    }

    @Test func theMetaBackdropFillsASeedWithoutOne() {
        let vm = viewModel(meta: meta(background: "https://x/meta.jpg"), seed: seed(background: nil))
        #expect(vm.backdropURL == URL(string: "https://x/meta.jpg"))
    }

    // MARK: - Fixtures

    private func viewModel(meta: Meta?, seed: MetaPreview?) -> MetaDetailViewModel {
        MetaDetailViewModel(
            meta: meta, enrichment: nil, related: [],
            typeID: "movie", metaID: "tt1", fallbackTitle: "Sample", seed: seed
        )
    }

    private func seed(background: String?) -> MetaPreview {
        MetaPreview(
            id: "tt1", type: "movie", name: "Sample", poster: nil, posterShape: nil,
            background: background, logo: nil, description: nil, releaseInfo: nil,
            imdbRating: nil, genres: nil
        )
    }

    private func meta(background: String?) -> Meta {
        Meta(
            id: "tt1", type: "movie", name: "Sample", poster: nil, background: background, logo: nil,
            description: nil, releaseInfo: nil, runtime: nil, imdbRating: nil, genres: nil,
            cast: nil, director: nil, videos: nil
        )
    }
}
