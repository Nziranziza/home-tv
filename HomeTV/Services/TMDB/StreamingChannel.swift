import Foundation

/// A streaming service shown as a channel: its TMDB watch provider (what it carries) and TMDB
/// network (its wordmark). Only ids live here — names are for accessibility, artwork loads at runtime.
struct StreamingChannel: Identifiable, Hashable, Sendable {
    let providerID: Int
    let networkID: Int
    let name: String

    var id: Int { providerID }

    /// US services, in row order.
    static let featured: [StreamingChannel] = [
        StreamingChannel(providerID: 8, networkID: 213, name: "Netflix"),
        StreamingChannel(providerID: 1899, networkID: 3186, name: "HBO Max"),
        StreamingChannel(providerID: 9, networkID: 1024, name: "Prime Video"),
        StreamingChannel(providerID: 337, networkID: 2739, name: "Disney+"),
        StreamingChannel(providerID: 350, networkID: 2552, name: "Apple TV"),
        StreamingChannel(providerID: 15, networkID: 453, name: "Hulu"),
        StreamingChannel(providerID: 2303, networkID: 4330, name: "Paramount+"),
        StreamingChannel(providerID: 386, networkID: 3353, name: "Peacock"),
        StreamingChannel(providerID: 43, networkID: 318, name: "STARZ"),
        StreamingChannel(providerID: 526, networkID: 4661, name: "AMC+"),
        StreamingChannel(providerID: 34, networkID: 6219, name: "MGM+"),
        StreamingChannel(providerID: 283, networkID: 1112, name: "Crunchyroll")
    ]
}
