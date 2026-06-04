import SwiftUI

struct ContinueWatchingRow: View {
    let items: [WatchHistoryItem]
    var onSelect: (WatchHistoryItem) -> Void = { _ in }

    private var rowHeight: CGFloat {
        Theme.Card.continueWatchingSize.height + Theme.Row.continueWatchingVerticalPadding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Row.headerSpacing) {
            RowHeader(title: "Continue Watching")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Row.continueWatchingCardSpacing) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item) { onSelect(item) }
                    }
                }
                .padding(.horizontal, Theme.Row.contentInset)
                .padding(.vertical, Theme.Row.continueWatchingVerticalPadding)
            }
            .scrollClipDisabled()
            .frame(height: rowHeight)
        }
        // One vertical focus target for the whole row (see ContentRow).
        .focusSection()
    }
}

/// Apple-style Continue Watching card: rounded landscape artwork with the show's title logo overlaid
/// (Apple bakes the title into key art; Stremio gives us a separate transparent `logo`, which we
/// overlay to match). A subtle bottom scrim keeps the title + controls legible on any artwork.
private struct ContinueWatchingCard: View {
    let item: WatchHistoryItem
    var action: () -> Void = {}

    @State private var trakt = TraktService.shared

    private var size: CGSize { Theme.Card.continueWatchingSize }

    /// Real Trakt playback progress (0–1) for this title when signed in and available, otherwise the
    /// placeholder below so the card always matches Apple's layout.
    private var traktProgress: Double? { trakt.progress(forKey: item.metaID) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(
                    url: (item.background ?? item.poster).flatMap(URL.init(string:)),
                    targetSize: size,
                    contentMode: .fill
                ) {
                    Color(white: 0.12)
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                // Bottom scrim — keeps the title logo + controls clear over any artwork.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.45),
                        .init(color: .black.opacity(0.6), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                bottomContent
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.card)
        .accessibilityLabel("Resume \(item.name)")
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleArt
            controlsRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // The show's title logo (Apple-style), falling back to the name when no logo is available.
    @ViewBuilder
    private var titleArt: some View {
        if let logoURL = item.logo.flatMap(URL.init(string:)) {
            RemoteImage(url: logoURL, targetSize: CGSize(width: 260, height: 90), contentMode: .fit) {
                titleText
            }
            .frame(maxWidth: size.width * 0.62, maxHeight: 52, alignment: .leading)
            .accessibilityHidden(true)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            ProgressBar(progress: traktProgress ?? placeholderProgress)
                .frame(width: 56, height: 4)

            Text(timeText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            HomeTVSourceBadge()
                .scaleEffect(0.7)
        }
    }

    /// Real progress text when Trakt has playback for this title, else the placeholder. When real,
    /// we only know the percentage (no runtime), so we show that rather than a fabricated time.
    private var timeText: String {
        if let p = traktProgress {
            return "\(Int((p * 100).rounded()))% watched"
        }
        return placeholderTimeText
    }

    // MARK: - Placeholder resume data
    //
    // FALLBACK — used when not signed in to Trakt (or Trakt has no playback for this title). HomeTV
    // hands playback to Infuse/VLC, which never reports the position back, so there's no *local*
    // progress to show. These values are derived deterministically from the item id (stable across
    // launches, unlike `hashValue`) purely so the card matches Apple's layout.

    private var placeholderProgress: Double {
        0.2 + Double(Self.stableHash(item.id) % 60) / 100.0   // 0.20–0.79
    }

    private var placeholderTimeText: String {
        let hash = Self.stableHash(item.id)
        let minutesLeft = 8 + hash % 92                        // 8–99 min
        if item.typeID == "series" {
            let season = 1 + (hash / 7) % 4
            let episode = 1 + (hash / 3) % 9
            return "S\(season), E\(episode) · \(minutesLeft)m"
        }
        let hours = minutesLeft / 60
        let minutes = minutesLeft % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Deterministic across launches — Swift's `String.hashValue` is seeded per process.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return abs(hash)
    }
}
