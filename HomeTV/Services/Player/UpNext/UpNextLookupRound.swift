import Foundation

/// Which round of next-episode lookups is running. Credits can start the lookup early; if that round fails,
/// one more waits for `UpNextTiming.resolveLead`.
enum UpNextLookupRound {
    case early
    case awaitingLate
    case late
}
