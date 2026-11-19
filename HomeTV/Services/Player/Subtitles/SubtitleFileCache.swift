import CryptoKit
import Foundation

/// Repaired local copies of add-on SRT files, made the first time one is selected.
enum SubtitleFileCache {
    private static let directory = URL.cachesDirectory.appending(path: "Subtitles")

    /// A repaired copy of the SRT at `url`, or nil when it isn't SRT or can't be fetched; the player then
    /// reads the original.
    static func localCopy(of url: URL) async -> URL? {
        let file = directory.appending(path: name(for: url))
        if FileManager.default.fileExists(atPath: file.path()) { return file }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252),
              let repaired = SubtitleFileRepair.repaired(text) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repaired.utf8).write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// Named by the URL's hash; the `.srt` extension tells the player its format.
    private static func name(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }
        return hex.joined() + ".srt"
    }
}
