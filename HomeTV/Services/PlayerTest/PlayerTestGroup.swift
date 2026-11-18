import Foundation

struct PlayerTestGroup: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let items: [PlayerTestItem]
}
