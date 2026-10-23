/// The line above an episode's show name in the player: `S2, E1 • The Engineer`, the way the system
/// player writes it.
enum PlayerEpisodeLabel {
    static func text(season: Int, episode: Int, title: String?) -> String {
        let numbers = "S\(season), E\(episode)"
        guard let title, !title.isEmpty else { return numbers }
        return "\(numbers) • \(title)"
    }
}
