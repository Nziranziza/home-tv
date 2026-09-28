import Foundation

/// When the detail page reveals its content: once the base meta has loaded and TMDB enrichment has
/// settled, or once `cap` has passed since the meta landed, so a slow TMDB never holds the page.
struct DetailReadiness: Equatable {
    /// How long a loaded page waits on enrichment before revealing anyway.
    static let cap: Duration = .milliseconds(1200)

    var metaLoaded = false
    var enrichmentSettled = false
    var capElapsed = false

    var isReady: Bool { metaLoaded && (enrichmentSettled || capElapsed) }

    /// Everything settled at once (the offline preview path).
    static let settled = DetailReadiness(metaLoaded: true, enrichmentSettled: true, capElapsed: true)
}
