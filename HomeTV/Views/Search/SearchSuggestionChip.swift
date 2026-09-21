import SwiftUI

/// One suggestion pill: a magnifier glyph plus the suggested term. A real `Button`, so the focus
/// engine drives the row and the Select button applies the term.
struct SearchSuggestionChip: View {
    let term: String
    var action: () -> Void = {}

    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Search.chipGlyphSpacing) {
                Image(systemName: "magnifyingglass")
                Text(term)
                    .lineLimit(1)
            }
            .font(.title3)
            .foregroundStyle(focused ? theme.primaryText : theme.secondaryText)
            .padding(.horizontal, Theme.Search.chipHorizontalPadding)
            .padding(.vertical, Theme.Search.chipVerticalPadding)
            .background(
                Capsule().fill(focused ? theme.cardFocused : theme.cardRest)
            )
        }
        .buttonStyle(CardFocusStyle())
        .buttonBorderShape(.capsule)
        .focused($focused)
        .animation(.easeInOut(duration: Theme.Card.focusAnimationDuration), value: focused)
        .accessibilityLabel("Search for \(term)")
    }
}
