import SwiftUI

/// TMDB attribution, required by The Movie Database's API terms of use (logo + the "not endorsed or
/// certified" statement). Styled as a non-focusable sibling of the settings rows — TMDB logo in the
/// icon slot, title + disclaimer beside it — so it matches the carded look of the rest of Settings,
/// rather than reading as a bare footer. Kept off the Apple-TV+-styled detail screen.
struct TMDBAttributionView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 28) {
            Image("TMDBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56)
                .accessibilityLabel("The Movie Database")
            VStack(alignment: .leading, spacing: 6) {
                Text("Metadata provided by TMDB")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, Theme.Spacing.rowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(theme.cardRest)
        )
    }
}
