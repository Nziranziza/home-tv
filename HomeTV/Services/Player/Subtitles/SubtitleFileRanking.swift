/// Orders a language's add-on files by how likely they are to be in sync with the stream: the same release
/// group, then the same frame rate, then the same source, then the same resolution.
enum SubtitleFileRanking {
    static func score(_ file: ExternalSubtitle, streamFilename: String?, frameRate: Double?) -> Int {
        var score = 0
        if let streamFilename {
            let stream = SubtitleRelease(name: streamFilename)
            let release = SubtitleRelease(name: [file.releaseName, file.releaseFormat].compactMap { $0 }.joined(separator: " "))
            let group = file.releaseGroup?.lowercased() ?? release.group
            if let group, group == stream.group { score += 8 }
            if let source = release.source, source == stream.source { score += 2 }
            if let resolution = release.resolution, resolution == stream.resolution { score += 1 }
        }
        if let frameRate, let fileRate = file.frameRate, abs(frameRate - fileRate) < 0.05 { score += 4 }
        return score
    }

    /// Add-on file tracks best first; equal scores keep the add-on's order. `files` is the engine's list
    /// the tracks index into.
    static func ranked(
        _ tracks: [PlaybackTrack],
        files: [ExternalSubtitle],
        streamFilename: String?,
        frameRate: Double?
    ) -> [PlaybackTrack] {
        let scores = tracks.map { track in
            ExternalSubtitle.index(of: track)
                .flatMap { files.indices.contains($0) ? files[$0] : nil }
                .map { score($0, streamFilename: streamFilename, frameRate: frameRate) } ?? 0
        }
        return tracks.indices
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            .map { tracks[$0] }
    }
}
