import SwiftUI

struct PlayerPickerView: View {
    @State private var preference = PlayerPreference.shared
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

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
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.vertical, 60)
            }
            .pageHorizontalInsets()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct PlayerRow: View {
    let player: ExternalPlayer
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(theme.tertiaryText, lineWidth: 2)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Circle()
                        .fill(theme.primaryText)
                        .frame(width: 22, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(player.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text(detail(for: player))
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)

            if !player.isInstalled && player != .system {
                Text("Not Installed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(theme.cardRest)
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
