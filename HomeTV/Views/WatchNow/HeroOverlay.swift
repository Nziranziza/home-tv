import SwiftUI

/// The Watch Now hero's **scrolling** layer: the per-title logo/metadata/tagline, the action row
/// (Play + Watchlist + Info + Next, where Watchlist shows only when signed in to Trakt and Next pages
/// the carousel), and the page dots. It has a transparent background and scrolls up over the pinned
/// `HeroBackdropLayer`, sliding under the top as the content sheet rises.
///
/// Reads the shared `HeroCarouselModel` for the current item and paging; writes focus state back so
/// the model's auto-advance pauses while a control is aimed.
struct HeroOverlay: View {
    let model: HeroCarouselModel
    /// Trakt, read for the watchlist toggle's signed-in / in-list state (re-renders the button when the
    /// list changes) and mutated when the user toggles it — same pattern as the detail hero.
    let trakt: TraktService
    var defaultFocusNamespace: Namespace.ID?
    var onPlay: (MetaPreview) -> Void = { _ in }
    var onInfo: (MetaPreview) -> Void = { _ in }

    @FocusState private var focusedControl: HeroControl?

    enum HeroControl: Hashable { case play, watchlist, info, next }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HeroContentColumn(
                model: model,
                trakt: trakt,
                focus: $focusedControl,
                defaultFocusNamespace: defaultFocusNamespace,
                onPlay: onPlay,
                onInfo: onInfo
            )
            if model.canPage {
                HeroPageDots(count: model.items.count, current: model.index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Theme.Hero.pageDotsBottomPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Keep the model's focus gate in sync so its timer doesn't shift content under an aimed button.
        .onChange(of: focusedControl) { _, new in model.isControlFocused = (new != nil) }
    }

}

// MARK: - Content column

/// The hero's bottom-anchored text/art + action row column, split into its own `View` (not a computed
/// property) so the body stays composed of real `View` types. The text/art block crossfades per page
/// (keyed by item id); the action row below does NOT carry an id, so it persists across pages and keeps
/// the user's focus while they page left/right. The whole block is bottom-anchored, so a taller info
/// block grows upward and the buttons stay put.
private struct HeroContentColumn: View {
    let model: HeroCarouselModel
    let trakt: TraktService
    var focus: FocusState<HeroOverlay.HeroControl?>.Binding
    var defaultFocusNamespace: Namespace.ID?
    let onPlay: (MetaPreview) -> Void
    let onInfo: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Hero.contentSpacing) {
            ZStack(alignment: .bottomLeading) {
                if let meta = model.currentItem {
                    HeroInfo(meta: meta)
                        .id(meta.id)
                        .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)

            if let meta = model.currentItem {
                HeroActionRow(
                    focus: focus,
                    canPage: model.canPage,
                    defaultFocusNamespace: defaultFocusNamespace,
                    onPlay: { onPlay(meta) },
                    showWatchlist: trakt.isSignedIn,
                    inWatchlist: trakt.isInWatchlist(imdb: meta.id),
                    onWatchlist: { trakt.toggleWatchlist(type: meta.type, imdb: meta.id) },
                    onInfo: { onInfo(meta) },
                    onPagePrevious: { model.advance(by: -1) },
                    onPageNext: { model.advance(by: 1) }
                )
            }
        }
        .padding(.horizontal, Theme.Hero.horizontalPadding)
        .padding(.bottom, Theme.Hero.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// Horizontal page-slide following the paging direction, shared with the backdrop so the whole
    /// hero pages as one.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: model.forward ? .trailing : .leading),
            removal: .move(edge: model.forward ? .leading : .trailing)
        )
    }
}

// MARK: - Content

/// The per-page art/text: logo or title, metadata chips, tagline. Crossfades on page change.
private struct HeroInfo: View {
    let meta: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Hero.contentSpacing) {
            HeroTitle(meta: meta)
            HeroMetaChips(meta: meta)
            if let tagline {
                HeroTagline(text: tagline)
            }
        }
    }

    private var tagline: String? {
        guard let desc = meta.description, !desc.isEmpty else { return nil }
        return desc
            .split(separator: ". ", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? desc
    }
}

private struct HeroTitle: View {
    let meta: MetaPreview

    var body: some View {
        if let url = meta.logo.flatMap(URL.init(string:)) {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: Theme.Hero.logoMaxWidth, height: Theme.Hero.logoMaxHeight),
                contentMode: .fit
            ) {
                HeroTitleText(name: meta.name)
            }
            .frame(
                maxWidth: Theme.Hero.logoMaxWidth,
                maxHeight: Theme.Hero.logoMaxHeight,
                alignment: .bottomLeading
            )
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .accessibilityLabel(meta.name)
        } else {
            HeroTitleText(name: meta.name)
        }
    }
}

/// The plain text title, shown when a title has no logo image (and as the logo's load placeholder). Its
/// own `View` rather than a computed property so both call sites share one real view type.
private struct HeroTitleText: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 78, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.7), radius: 12, y: 4)
            .frame(maxWidth: Theme.Hero.titleMaxWidth, alignment: .leading)
    }
}

private struct HeroMetaChips: View {
    let meta: MetaPreview
    /// Streaming-provider / network badge for the featured title (nil → no badge). Resolved lazily per
    /// page via the shared, cached TMDB enrichment.
    @State private var providerBadgeURL: URL?

    var body: some View {
        MetaChipRow(parts: chips, trailingBadge: ratingText, leading: .provider(providerBadgeURL))
            .task(id: meta.id) {
                providerBadgeURL = await TMDBService.shared
                    .enrich(stremioType: meta.type, imdbID: meta.id)?.providerBadgeURL
            }
    }

    private var chips: [String] {
        var parts: [String] = [StremioType.displayLabel(for: meta.type)]
        if let year = meta.releaseInfo, !year.isEmpty { parts.append(year) }
        if let genres = meta.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        return parts
    }

    private var ratingText: String? {
        guard let rating = meta.imdbRating, !rating.isEmpty else { return nil }
        return "IMDb \(rating)"
    }
}

private struct HeroTagline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: Theme.Hero.taglineMaxWidth, alignment: .leading)
    }
}

private struct HeroActionRow: View {
    var focus: FocusState<HeroOverlay.HeroControl?>.Binding
    let canPage: Bool
    var defaultFocusNamespace: Namespace.ID?
    let onPlay: () -> Void
    /// Watchlist toggle: shown only when signed in to Trakt; `inWatchlist` drives the plus/checkmark.
    let showWatchlist: Bool
    let inWatchlist: Bool
    let onWatchlist: () -> Void
    let onInfo: () -> Void
    let onPagePrevious: () -> Void
    let onPageNext: () -> Void

    var body: some View {
        HStack(spacing: Theme.Hero.actionRowSpacing) {
            HeroPlayButton(title: "Play", icon: "play.fill", action: onPlay)
                .focused(focus, equals: .play)
                // Make Play the focus the engine lands on when entering Watch Now from the tab bar,
                // instead of the centered Continue Watching row below.
                .prefersHeroDefaultFocus(in: defaultFocusNamespace)
                // First button: a left press has no focus target, so it pages to the previous title.
                .onMoveCommand { if canPage, $0 == .left { onPagePrevious() } }

            // Watchlist toggle (plus → checkmark), wired to Trakt exactly like the detail hero. Shown
            // only when signed in — there's no watchlist to toggle when signed out (no dead control).
            if showWatchlist {
                HeroCircleButton(
                    icon: inWatchlist ? "checkmark" : "plus",
                    accessibilityLabel: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist",
                    action: onWatchlist
                )
                .focused(focus, equals: .watchlist)
            }

            HeroCircleButton(icon: "info", accessibilityLabel: "More Info", action: onInfo)
                .focused(focus, equals: .info)

            // Pages the hero carousel to the next title on Select (the chevron's natural meaning), and
            // also on a right press at this last button — no focus target lies right, mirroring Play's
            // left-press-to-previous. Shown only when there's more than one featured title to page to.
            if canPage {
                HeroCircleButton(icon: "chevron.right", accessibilityLabel: "Next", action: onPageNext)
                    .focused(focus, equals: .next)
                    .onMoveCommand { if $0 == .right { onPageNext() } }
            }
        }
        .padding(.top, Theme.Hero.actionRowTopPadding)
    }
}

private extension View {
    /// Applies `prefersDefaultFocus` only when a focus-scope namespace is supplied.
    @ViewBuilder
    func prefersHeroDefaultFocus(in namespace: Namespace.ID?) -> some View {
        if let namespace {
            prefersDefaultFocus(in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Page dots

/// Apple TV-style hero pager: a centered run of dots with the active page as an elongated white pill.
/// When there are more pages than fit, the run is windowed around the current page and dots shrink
/// toward the edges to hint that more exist beyond the window.
private struct HeroPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Theme.Hero.pageDotsSpacing) {
            ForEach(visibleRange, id: \.self) { i in
                let isActive = i == current
                Capsule()
                    .fill(isActive ? Color.white : Color.white.opacity(0.45))
                    .frame(
                        width: isActive ? Theme.Hero.pageDotActiveWidth : Theme.Hero.pageDotSize * scale(for: i),
                        height: Theme.Hero.pageDotSize * (isActive ? 1.0 : scale(for: i))
                    )
            }
        }
        .padding(.horizontal, Theme.Hero.pageDotsPillHorizontalPadding)
        .padding(.vertical, Theme.Hero.pageDotsPillVerticalPadding)
        .background(
            Capsule(style: .continuous).fill(.black.opacity(0.28))
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .animation(.easeInOut(duration: 0.35), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }

    /// Window of dots to draw, centered on the current page and clamped to the ends.
    private var visibleRange: Range<Int> {
        let maxVisible = Theme.Hero.pageDotsMaxVisible
        guard count > maxVisible else { return 0..<count }
        let half = maxVisible / 2
        var start = current - half
        var end = current + half + 1
        if start < 0 { end -= start; start = 0 }
        if end > count { start -= (end - count); end = count }
        return max(0, start)..<end
    }

    /// Dots shrink only at a window edge that has more pages hidden beyond it, so the indicator reads
    /// "there's more this way". When every page fits, all dots stay full size (Apple behaviour).
    private func scale(for index: Int) -> CGFloat {
        let range = visibleRange
        if range.upperBound < count {
            switch range.upperBound - 1 - index {
            case 0: return 0.45
            case 1: return 0.7
            default: break
            }
        }
        if range.lowerBound > 0 {
            switch index - range.lowerBound {
            case 0: return 0.45
            case 1: return 0.7
            default: break
            }
        }
        return 1.0
    }
}
