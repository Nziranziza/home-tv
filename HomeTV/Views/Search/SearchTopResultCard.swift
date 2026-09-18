import SwiftUI

/// One Top Results entry: a small poster beside the title and its "TV Show · Sci-Fi" descriptor, on a
/// wide rounded platter. Unlike the poster cards elsewhere on the screen, the title is spelled out —
/// this row is the screen's answer to "did you mean this?", so it never relies on artwork alone.
struct SearchTopResultCard: View {
    let meta: MetaPreview
    var action: () -> Void = {}

    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Search.topResultContentSpacing) {
                poster
                VStack(alignment: .leading, spacing: Theme.Search.topResultTextSpacing) {
                    Text(meta.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(SearchResultSubtitle.text(for: meta))
                        .font(.body)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Search.topResultPadding)
            .frame(width: Theme.Search.topResultSize.width,
                   height: Theme.Search.topResultSize.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(focused ? theme.cardFocused : theme.cardRest)
            )
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(CardFocusStyle())
        .focused($focused)
        .animation(.easeInOut(duration: Theme.Card.focusAnimationDuration), value: focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meta.name), \(SearchResultSubtitle.text(for: meta))")
        .accessibilityAddTraits(.isButton)
    }

    private var poster: some View {
        RemoteImage(url: meta.poster.flatMap(URL.init(string:)),
                    targetSize: Theme.Search.topResultPosterSize, contentMode: .fill) {
            RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                .fill(theme.cardRest)
        }
        .frame(width: Theme.Search.topResultPosterSize.width,
               height: Theme.Search.topResultPosterSize.height)
        .clipShape(.rect(cornerRadius: Theme.Radius.badge))
    }
}
