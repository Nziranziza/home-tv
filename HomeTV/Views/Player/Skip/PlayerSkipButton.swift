import SwiftUI

/// Skip Intro, Skip Recap or Skip Credits, in the lower right while the bar is hidden: the system
/// player's contextual action, which holds focus until it's used or dismissed.
struct PlayerSkipButton: View {
    let segment: SkipSegment
    let focus: FocusState<PlayerFocus?>.Binding
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(segment.kind.title)
                .font(.caption)
                .bold()
                .padding(.horizontal, 43)
                .padding(.vertical, 15)
        }
        .buttonStyle(.playerTab)
        .focused(focus, equals: .skipSegment)
        // Measured against AVPlayerViewController's contextual action.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 106)
        .padding(.bottom, 61)
    }
}
