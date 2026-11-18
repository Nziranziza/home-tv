import SwiftUI

/// Skip Intros & Credits, On or Off, as a Settings row that toggles on Select.
struct SkipSegmentsSettingRow: View {
    @Bindable var preference: PlayerPreference
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            preference.skipsSegments.toggle()
        } label: {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skip Intros & Credits")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Offer Skip Intro, Skip Recap and Skip Credits while they play in HomeTV.")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                Text(preference.skipsSegments ? "On" : "Off")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .buttonStyle(SettingsCardStyle())
    }
}
