import SwiftUI

/// Plays the file in HomeTV, with an Infuse button beside it for comparison. Focusing either one shows
/// the file in the detail panel.
struct PlayerTestItemRow: View {
    let library: PlayerTestLibrary
    let entry: PlayerTestEntry
    let selection: PlayerTestSelection
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isInfuseFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Button {
                Task { await library.play(entry.item, expect: entry.expect, in: .builtIn) }
            } label: {
                HStack {
                    Image(systemName: entry.expect.symbol).foregroundStyle(entry.expect.tint)
                    VStack(alignment: .leading) {
                        Text(entry.item.title).lineLimit(1)
                        Text(entry.item.detailLine)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.primaryText)
                }
            }
            .buttonStyle(SettingsCardStyle())
            .focused($isPlayFocused)

            if library.isInfuseInstalled {
                Button("Infuse", systemImage: "arrow.up.forward.app") {
                    Task { await library.play(entry.item, expect: entry.expect, in: .infuse) }
                }
                .buttonStyle(.bordered)
                .disabled(entry.item.infuseBlockReason != nil)
                .focused($isInfuseFocused)
                .fixedSize()
            }
        }
        .onChange(of: isPlayFocused || isInfuseFocused) { _, isFocused in
            if isFocused { selection.entry = entry }
        }
    }
}
