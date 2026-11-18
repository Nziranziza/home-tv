import Foundation

struct PlayerTestSection: Decodable, Identifiable, Sendable {
    /// The Codec Matrix, which gets filters instead of a groups list.
    static let matrixID = "matrix"

    let id: String
    let title: String
    let summary: String?
    let expect: PlayerTestExpectation
    let groups: [PlayerTestGroup]

    var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
}
