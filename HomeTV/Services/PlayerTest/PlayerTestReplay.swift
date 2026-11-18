import Foundation

/// The last sample played and where, so it can be replayed straight after a fix.
struct PlayerTestReplay: Codable, Sendable {
    let item: PlayerTestItem
    let expect: PlayerTestExpectation
    let player: ExternalPlayer
}
