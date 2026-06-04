import SwiftUI

struct SettingsView: View {
    @State private var path: [SettingsRoute] = SettingsView.initialPath()

    enum SettingsRoute: Hashable { case addons, player }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        ScreenTitle(title: "Settings")
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink {
                                AddonManagerView()
                            } label: {
                                settingsRow(
                                    icon: "puzzlepiece.extension.fill",
                                    title: "Addons",
                                    subtitle: "Manage Stremio addons that supply catalogs and streams"
                                )
                            }
                            .buttonStyle(SettingsCardStyle())

                            NavigationLink {
                                PlayerPickerView()
                            } label: {
                                settingsRow(
                                    icon: "play.rectangle.fill",
                                    title: "Default Player",
                                    subtitle: "Choose which app receives the stream handoff"
                                )
                            }
                            .buttonStyle(SettingsCardStyle())

                            // Trakt is only surfaced when the app was built with API credentials
                            // (see TraktConfig). Without them there's no working sign-in, so the
                            // row is hidden rather than showing developer setup instructions.
                            if TraktConfig.isConfigured {
                                TraktSettingsRow()
                            }

                            // TMDB attribution is required by their API terms whenever enrichment runs;
                            // shown here (not on the detail screen) to keep that UI pure Apple TV+.
                            if TMDBConfig.isConfigured {
                                TMDBAttributionView()
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("HomeTV")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.Color.primaryText)
                            Text("Stremio client. v0.1")
                                .font(.callout)
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .padding(.horizontal, Theme.Spacing.rowHorizontal)
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 36)
                    .padding(.bottom, 60)
                    .frame(maxWidth: 1400, alignment: .leading)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .addons: AddonManagerView()
                case .player: PlayerPickerView()
                }
            }
        }
    }

    private static func initialPath() -> [SettingsRoute] {
        switch ProcessInfo.processInfo.environment["INITIAL_SETTINGS"] {
        case "addons": [.addons]
        case "player": [.player]
        default: []
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 28) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.Color.tertiaryText)
        }
    }
}
