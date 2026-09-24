import Foundation
import Testing
@testable import HomeTV

/// The discover queries behind each channel shelf.
struct ChannelShelfTests {
    private let today = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func everyQueryIsScopedToTheProviderAndRegion() {
        for shelf in [ChannelShelf.topTen] + ChannelShelf.rows {
            for media in shelf.media {
                let parameters = shelf.parameters(media: media, providerID: 8, region: "US", today: today)
                #expect(parameters["with_watch_providers"] == "8")
                #expect(parameters["watch_region"] == "US")
            }
        }
    }

    @Test func shelfIDsAreUnique() {
        let ids = ([ChannelShelf.topTen] + ChannelShelf.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func genreShelvesFilterByGenre() throws {
        let comedy = try #require(ChannelShelf.rows.first { $0.id == "comedy" })
        #expect(comedy.parameters(media: .tv, providerID: 8, region: "US", today: today)["with_genres"] == "35")
    }

    @Test func recentShelvesUseEachMediaTypesOwnDateField() throws {
        let recent = try #require(ChannelShelf.rows.first { $0.id == "new" })
        let movies = recent.parameters(media: .movie, providerID: 8, region: "US", today: today)
        let shows = recent.parameters(media: .tv, providerID: 8, region: "US", today: today)
        #expect(movies["primary_release_date.lte"] == TMDBConfig.day(today))
        #expect(movies["first_air_date.lte"] == nil)
        #expect(shows["first_air_date.gte"] == TMDBConfig.day(TMDBConfig.date(90, daysBefore: today)))
    }

    @Test func topRatedNeedsMoreVotesThanPopular() throws {
        let topRated = try #require(ChannelShelf.rows.first { $0.id == "top-rated-tv" })
        let popular = try #require(ChannelShelf.rows.first { $0.id == "popular-tv" })
        let topVotes = Int(topRated.parameters(media: .tv, providerID: 8, region: "US", today: today)["vote_count.gte"] ?? "")
        let popularVotes = Int(popular.parameters(media: .tv, providerID: 8, region: "US", today: today)["vote_count.gte"] ?? "")
        #expect((topVotes ?? 0) > (popularVotes ?? 0))
    }

    @Test func featuredChannelsAreDistinct() {
        let ids = StreamingChannel.featured.map(\.providerID)
        #expect(Set(ids).count == ids.count)
    }
}
