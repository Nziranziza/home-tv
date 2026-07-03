import Foundation

/// Which region currently holds focus on a detail-style screen. Crossing the hero↔content boundary
/// drives the full-viewport collapse scroll. Shared by the title detail (`MetaDetailView`) and the
/// single-episode detail (`EpisodeDetailView`) so both use the same scaffold wiring.
enum DetailZone: Hashable { case hero, content }
