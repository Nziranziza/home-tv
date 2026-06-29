import SwiftUI

/// The expanded-biography popover: a frosted dark card with the person's name and full biography,
/// anchored just below the header bio over a dimmed page (the card blurs the artwork behind it, as in
/// the reference). A short bio sizes the card to fit; a long one caps the card and scrolls inside it.
/// The Menu/Back button dismisses it (intercepted with `onExitCommand` so Back closes the popover
/// rather than popping the navigation stack).
struct CastBioPopover: View {
    let name: String
    let biography: String
    let onDismiss: () -> Void

    @FocusState private var focused: Bool

    /// Anchor + sizing tuned to the reference: the card starts under the header bio, roughly aligned
    /// with the headshot's right half, and is wide enough for a comfortable measure.
    private let cardLeading: CGFloat = 455
    private let cardTop: CGFloat = 250
    private let cardWidth: CGFloat = 860
    private let bioMaxHeight: CGFloat = 520

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dimmed page behind; the frosted card blurs it (faint artwork shows through), as in the reference.
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            card
                .padding(.leading, cardLeading)
                .padding(.top, cardTop)
        }
        .onExitCommand(perform: onDismiss)
        .onAppear { focused = true }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            // Hug a short bio; scroll a long one. `ViewThatFits` keeps the plain text when it fits the
            // offered height, falling back to a focusable (d-pad scrollable) ScrollView when it doesn't.
            ViewThatFits(in: .vertical) {
                bioText
                ScrollView { bioText }
                    .scrollIndicators(.hidden)
                    .focusable()
                    .focused($focused)
            }
            .frame(maxHeight: bioMaxHeight)
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // Darken the colourful poster bleed so the card reads as a calm dark panel.
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(.black.opacity(0.28))
                }
        }
    }

    private var bioText: some View {
        Text(biography)
            .font(.system(size: 29))
            .foregroundStyle(.white.opacity(0.78))
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
