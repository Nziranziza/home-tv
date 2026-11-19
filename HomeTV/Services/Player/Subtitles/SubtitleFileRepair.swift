import Foundation

/// Rebuilds a hand-made SRT the way Stremio's converter reads it: timestamps with stray spaces are
/// fixed, and a cue whose timing line doesn't parse is dropped rather than guessed. A misread timing
/// line can otherwise leave one cue on screen for minutes.
enum SubtitleFileRepair {
    struct Cue: Equatable {
        var start: Int
        var end: Int
        var lines: [String]
    }

    /// Clean SRT, or nil when `text` isn't SRT or has no usable cue.
    static func repaired(_ text: String) -> String? {
        let cues = cues(in: text)
        guard !cues.isEmpty else { return nil }
        return cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.lines.joined(separator: "\n"))"
        }
        .joined(separator: "\n\n") + "\n"
    }

    static func cues(in text: String) -> [Cue] {
        var body = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") else { return [] }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var cues: [Cue] = []
        var current: Cue?
        for (index, line) in lines.enumerated() {
            if let timing = timing(line) {
                if let cue = current { cues.append(cue) }
                current = Cue(start: timing.start, end: timing.end, lines: [])
            } else if line.isEmpty {
                if let cue = current { cues.append(cue) }
                current = nil
            } else if line.allSatisfy(\.isNumber), index + 1 < lines.count, timing(lines[index + 1]) != nil {
                // The next cue's number.
                continue
            } else if current != nil {
                current?.lines.append(line)
            }
            // Text outside a cue belongs to a timing line that didn't parse, and is dropped with it.
        }
        if let cue = current { cues.append(cue) }
        return cues.filter { !$0.lines.isEmpty && $0.end > $0.start }
    }

    /// `00:03:49,437 --> 00:03: 52,189`, spaces inside the times allowed, in milliseconds.
    private static func timing(_ line: String) -> (start: Int, end: Int)? {
        let pattern = /^\s*(\d{1,2}\s*:\s*\d{1,2}\s*:\s*\d{1,2}\s*[,.]\s*\d{1,3})\s*-->\s*(\d{1,2}\s*:\s*\d{1,2}\s*:\s*\d{1,2}\s*[,.]\s*\d{1,3})/
        guard let match = line.firstMatch(of: pattern),
              let start = milliseconds(String(match.output.1)),
              let end = milliseconds(String(match.output.2)) else { return nil }
        return (start, end)
    }

    private static func milliseconds(_ time: String) -> Int? {
        let parts = time.split { !$0.isNumber }.compactMap { Int($0) }
        let digits = time.split { !$0.isNumber }
        guard parts.count == 4, let fraction = digits.last else { return nil }
        let ms = parts[3] * [100, 10, 1][min(fraction.count, 3) - 1]
        return ((parts[0] * 60 + parts[1]) * 60 + parts[2]) * 1000 + ms
    }

    private static func timestamp(_ ms: Int) -> String {
        let hours = ms / 3_600_000
        let minutes = ms / 60000 % 60
        let seconds = ms / 1000 % 60
        func padded(_ value: Int, _ width: Int) -> String {
            String(repeating: "0", count: max(0, width - String(value).count)) + String(value)
        }
        return "\(padded(hours, 2)):\(padded(minutes, 2)):\(padded(seconds, 2)),\(padded(ms % 1000, 3))"
    }
}
