import SwiftUI

/// Search, replay the last file, and files stored on this Apple TV.
struct PlayerTestHomeActions: View {
    let library: PlayerTestLibrary

    var body: some View {
        HStack {
            NavigationLink(value: PlayerTestRoute.all) {
                Label("Search All Files", systemImage: "magnifyingglass")
            }
            .disabled(library.index == nil)

            if let replay = library.lastPlayed {
                Button {
                    Task { await library.play(replay.item, expect: replay.expect, in: replay.player) }
                } label: {
                    Label("Replay \(replay.item.title) in \(replay.player.displayName)",
                          systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                }
                .frame(maxWidth: 900, alignment: .leading)
            }

            NavigationLink(value: PlayerTestRoute.local) {
                Label("On This Apple TV (\(library.localFiles.count))", systemImage: "internaldrive")
            }
        }
        .buttonStyle(.bordered)
        .focusSection()
    }
}
