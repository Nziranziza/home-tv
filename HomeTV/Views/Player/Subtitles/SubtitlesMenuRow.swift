/// A Subtitles menu row's focus identity. Fixed rows go by position; tracks and add-on languages by
/// identity, so a list reordered by late files keeps focus on the same row.
enum SubtitlesMenuRow: Hashable {
    case position(Int)
    case track(Int32)
    case language(String?)
}
