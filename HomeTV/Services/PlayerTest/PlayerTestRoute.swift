import Foundation

/// A screen the test library pushes: everything, a catalog section, a quick test, or local files.
enum PlayerTestRoute: Hashable, Sendable {
    case all
    case section(String)
    case preset(String)
    case local
}
