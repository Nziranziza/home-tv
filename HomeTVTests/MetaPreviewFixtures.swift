import Foundation
@testable import HomeTV

/// Compact `MetaPreview` builder for the search tests — every field the ranker reads is a parameter,
/// everything else is nil.
enum Fixture {
    static func meta(
        _ name: String,
        id: String? = nil,
        type: String = "series",
        genres: [String]? = nil,
        rating: String? = nil,
        releaseInfo: String? = nil
    ) -> MetaPreview {
        MetaPreview(
            id: id ?? name,
            type: type,
            name: name,
            poster: nil,
            posterShape: nil,
            background: nil,
            logo: nil,
            description: nil,
            releaseInfo: releaseInfo,
            imdbRating: rating,
            genres: genres
        )
    }
}
