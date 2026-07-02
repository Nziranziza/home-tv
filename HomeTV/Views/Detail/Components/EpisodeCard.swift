import SwiftUI

// MARK: - Episode card

/// An episode entry = TWO separate stacked focusable buttons, matching Apple:
///  • the thumbnail is its own button with the standard tvOS card focus (lift + specular); selecting it
///    plays the episode (`action`);
///  • the description is a second button that opens the episode detail screen (`onOpenDetail`), showing
///    a translucent container while the card is active (either element focused).
struct EpisodeCard: View {
    let thumbnailURL: URL?
    let episodeNumber: Int
    let title: String
    let overview: String?
    let dateText: String?
    let durationText: String
    let ratingText: String
    /// Watch progress (0–1) from Trakt playback. `nil` = not in progress, so no play indicator is
    /// shown (matches Apple: the play glyph only appears on an episode you've already started).
    var progress: Double? = nil
    /// Whether this episode is marked watched on Trakt — shows a checkmark badge.
    var watched: Bool = false
    /// Whether this is the episode the hero Play will play — shows an "Up Next" badge.
    var isUpNext: Bool = false
    /// Reports focus gain/loss to the parent so the season selector can track which season the
    /// in-view episode belongs to as you scroll across the continuous strip. Reports true while EITHER
    /// element (image or description) is focused.
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Secondary action (long-press): toggle this episode's watched state. Hidden when nil.
    var onToggleWatched: (() -> Void)? = nil
    /// Selecting the description — opens the episode detail screen.
    var onOpenDetail: () -> Void = {}
    /// Selecting the thumbnail — plays the episode.
    let action: () -> Void

    /// The thumbnail's focus. Drives the image lift and the gap that lets it clear the description.
    @FocusState private var imageFocused: Bool
    /// The description's focus.
    @FocusState private var descriptionFocused: Bool

    /// The card is "active" while either element is focused — the description panel shows in both states,
    /// with only the image's card lift distinguishing which element holds focus (matches Apple).
    private var active: Bool { imageFocused || descriptionFocused }

    // Sized so 4 cards are fully visible with the 5th peeking (88pt gutter + 4×400 + 3×28 = 1772,
    // 5th starts at 1800 within the 1920pt width) — matches Apple TV's episode row.
    private let width: CGFloat = 400
    private let imageHeight: CGFloat = 225

    var body: some View {
        // When the image is focused it lifts/scales (.card); open the gap enough that the lifted image
        // clears the description (rather than overlapping it), animating in step with the card. The
        // description gaining focus doesn't lift the image, so the gap stays closed.
        VStack(alignment: .leading, spacing: imageFocused ? 28 : 8) {
            imageButton
            descriptionButton
        }
        .frame(width: width)
        .animation(.easeOut(duration: 0.25), value: imageFocused)
        .onChange(of: active) { _, isActive in onFocusChange(isActive) }
    }

    private var imageButton: some View {
        Button(action: action) {
            RemoteImage(url: thumbnailURL, targetSize: CGSize(width: width, height: imageHeight), contentMode: .fill) {
                Color(white: 0.1)
            }
            .frame(width: width, height: imageHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { durationOverlay }
            .overlay(alignment: .topTrailing) { watchedBadge }
            .overlay(alignment: .topLeading) { upNextBadge }
        }
        .buttonStyle(.card)
        .focused($imageFocused)
        // Long-press (select hold) reveals the watched toggle — click still plays.
        .contextMenu {
            if let onToggleWatched {
                Button {
                    onToggleWatched()
                } label: {
                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                          systemImage: watched ? "eye.slash" : "eye")
                }
            }
        }
    }

    @ViewBuilder
    private var upNextBadge: some View {
        if isUpNext {
            Text("UP NEXT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white))
                .padding(10)
        }
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if watched {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .padding(10)
        }
    }

    private var durationOverlay: some View {
        HStack(spacing: 8) {
            if let progress {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 90, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: 90 * progress, height: 4)
                    }
            }
            Text(durationText)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.bottom, 10)
    }

    /// The description — its own focusable button that opens the episode detail screen. It shows the
    /// translucent panel while the card is active (either element focused) rather than swapping its
    /// button style on focus (a style swap would drop focus mid-move on tvOS).
    private var descriptionButton: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EPISODE \(episodeNumber)")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.55))
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.7))
                        // Always reserve two lines so the block height is identical focused/unfocused
                        // (no reflow from one line to two when focus toggles).
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if let dateText {
                        Text(dateText)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(ratingText)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(.white.opacity(0.5), lineWidth: 1.2)
                        )
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: width, alignment: .topLeading)
            // Translucent container while the card is active (either element focused); plain text at rest.
            .background(active ? Color.black.opacity(0.3) : Color.clear)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .animation(.easeOut(duration: 0.18), value: active)
        }
        .buttonStyle(EpisodeDescriptionButtonStyle())
        .focused($descriptionFocused)
    }
}

/// A focusable style for the episode description that adds no platter or lift of its own — the tvOS
/// `.plain`/`.card` styles would overlay their own focus highlight, but Apple's episode description
/// cues focus only with the card's translucent panel (driven by the card's `active` state). This custom
/// style renders the label as-is so that panel is the sole focus cue, dimming slightly while pressed.
private struct EpisodeDescriptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

