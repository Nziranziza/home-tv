import SwiftUI

struct PlayerPickerView: View {
    @State private var preference = PlayerPreference.shared

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    ScreenTitle(
                        title: "Default Player",
                        subtitle: "Choose which app receives the stream handoff. Infuse handles HTTP and magnet links; VLC handles direct HTTP only."
                    )

                    VStack(spacing: 12) {
                        ForEach(ExternalPlayer.allCases) { player in
                            Button {
                                preference.defaultPlayer = player
                            } label: {
                                PlayerRow(
                                    player: player,
                                    isSelected: preference.defaultPlayer == player
                                )
                            }
                            .buttonStyle(SettingsCardStyle())
                            .disabled(!player.isInstalled && player != .system)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
                .frame(maxWidth: 1400, alignment: .leading)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct PlayerRow: View {
    let player: ExternalPlayer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Theme.Color.tertiaryText, lineWidth: 2)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Circle()
                        .fill(Theme.Color.primaryText)
                        .frame(width: 22, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(player.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(detail(for: player))
                    .font(.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer(minLength: 0)

            if !player.isInstalled && player != .system {
                Text("Not Installed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Theme.Color.cardRest)
                    )
            }
        }
    }

    private func detail(for player: ExternalPlayer) -> String {
        switch player {
        case .infuse: "Recommended. Handles HTTP and magnet links."
        case .vlc: "Direct HTTP streams only. No magnet support."
        case .system: "Open with the system's default handler."
        }
    }
}
