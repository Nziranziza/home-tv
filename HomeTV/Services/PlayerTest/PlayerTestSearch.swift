import Foundation

/// Search text matching. Each query word must start a word of the entry, case- and accent-insensitively,
/// so `h.265`, `H265` and `hevc` all find HEVC files.
enum PlayerTestSearch {
    /// The words an entry is found by: each piece of a chunk, plus the chunk with its punctuation removed.
    static func words(_ text: String) -> [String] {
        var words = Set<String>()
        for chunk in fold(text).split(whereSeparator: \.isWhitespace) {
            let pieces = chunk.split { !isWordCharacter($0) }.map(String.init)
            words.formUnion(pieces)
            let compact = pieces.joined()
            if !compact.isEmpty { words.insert(compact) }
        }
        return Array(words)
    }

    static func tokens(_ query: String) -> [String] {
        fold(query)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0.filter(isWordCharacter)) }
            .filter { !$0.isEmpty }
    }

    static func matches(_ tokens: [String], words: [String]) -> Bool {
        tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "+"
    }
}
