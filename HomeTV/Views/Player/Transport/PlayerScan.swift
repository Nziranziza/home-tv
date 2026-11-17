import Foundation

/// A fast-forward or rewind: a direction and a level from 1 to 4, as on the system player.
struct PlayerScan: Equatable {
    enum Direction: Equatable {
        case forward
        case backward

        var sign: Double { self == .forward ? 1 : -1 }
    }

    /// Video seconds per second at each level, measured on the system player.
    static let speeds: [Double] = [8, 24, 48, 96]

    private(set) var direction: Direction
    private(set) var level = 1

    init(direction: Direction) {
        self.direction = direction
    }

    var rate: Double { direction.sign * Self.speeds[level - 1] }

    /// A click during the scan: the same side climbs a level and stays at the top; the other side steps
    /// down, and from level 1 reverses into level 1 the other way.
    mutating func click(_ side: Direction) {
        if side == direction {
            level = min(level + 1, Self.speeds.count)
        } else if level > 1 {
            level -= 1
        } else {
            direction = side
        }
    }
}
