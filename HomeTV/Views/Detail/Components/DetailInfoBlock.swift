import SwiftUI
import CoreText

// MARK: - Information block pieces

/// The one reusable frosted-panel look shared by the About card and the Information card: a
/// translucent `.ultraThinMaterial` fill (so the warm page gradient shows through), 22 pt corners,
/// and 24 pt internal padding. White content reads cleanly over it.
///
/// The content's *leading* edge stays at the layout guide (so it aligns with the section header), and
/// the frosted panel bleeds 24 pt further left as a background-only inset — matching the reference,
/// where the card edge sits left of the header while the card text aligns with it.
extension View {
    /// `padding` insets the content from the panel edge uniformly. Vertical + trailing are always real
    /// padding. When `bleedLeading` is true (default), the leading is supplied by the panel's
    /// negative-leading bleed so the text leading stays aligned with the section header while the panel
    /// edge sits `padding` further left. When false, the leading is a true padding (needed under a
    /// clipping style like `.card`, which would otherwise chop the bleed off).
    /// `showsBackground` toggles only the frosted panel — the padding is applied either way, so a card
    /// can appear/disappear on focus without the content shifting (used by the focus-aware info columns,
    /// which show the panel only while focused).
    func frostedInfoCard(padding: CGFloat = 24, bleedLeading: Bool = true, showsBackground: Bool = true) -> some View {
        self.padding(.vertical, padding)
            .padding(.trailing, padding)
            .padding(.leading, bleedLeading ? 0 : padding)
            .background {
                // Material gives the frost/blur; the white tint lifts it to the reference's lighter
                // translucent panel (≈ rgb 107,95,94) so it reads clearly over a dark backdrop, not
                // just over a bright one. Driven by opacity (not an `if`) so it can crossfade in/out on
                // focus rather than popping — the panel is otherwise always laid out.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(0.10))
                    )
                    .padding(.leading, bleedLeading ? -padding : 0)   // panel bleeds left of the text/header guide
                    .opacity(showsBackground ? 1 : 0)
            }
    }
}

/// Colour scheme for the Information block. The in-page sections render on the dark/translucent
/// background (white text); the centered expand overlay renders on a light frosted card (dark text) —
/// the inverse.
struct InfoPalette {
    let title: Color
    let label: Color
    let value: Color
    let more: Color
    let badge: Color
    let accessory: Color

    static let onDark = InfoPalette(
        title: .white,
        label: .white.opacity(0.5),
        value: Color(red: 0.929, green: 0.894, blue: 0.886),   // ≈ #EDE4E2
        more: .white,
        badge: .white.opacity(0.85),
        accessory: .white.opacity(0.78)
    )
    static let onLight = InfoPalette(
        title: .black.opacity(0.9),
        label: .black.opacity(0.5),
        value: .black.opacity(0.82),
        more: .black.opacity(0.9),
        badge: .black.opacity(0.7),
        accessory: .black.opacity(0.7)
    )
}

struct InfoColumnHeader: View {
    let title: String
    var palette: InfoPalette = .onDark

    var body: some View {
        // Large bold column header (Information / Languages / Accessibility) — distinct from the smaller
        // muted rail headers ("About", "Cast & Crew").
        Text(title)
            .font(.system(size: 43, weight: .bold))
            .foregroundStyle(palette.title)
            .padding(.bottom, 4)
    }
}

/// A label-over-value pair, e.g. "Released" / "2026". Long values tail-truncate to `lineLimit` with a
/// plain bold inline "MORE" cue (only in the in-page resting state; the overlay shows the full value).
struct InfoPair: View {
    let label: String
    let value: String
    var lineLimit: Int? = nil
    var palette: InfoPalette = .onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 20))
                .foregroundStyle(palette.label)
            InfoValueText(value: value, lineLimit: lineLimit, palette: palette)
        }
    }
}

/// The value text. When it overflows `lineLimit`, CoreText wraps it so the last visible line ends with an
/// ellipsis followed *inline* by a plain bold uppercase "MORE" cue (no box, no fill) — e.g.
/// "…Japanese (Dolby 5.1, AA… MORE". With no `lineLimit` (the overlay) it shows the full value.
///
/// Reused by the cast screen's biography (same Apple inline-MORE truncation), so it's `internal`.
struct InfoValueText: View {
    let value: String
    let lineLimit: Int?
    var fontSize: CGFloat = 24
    var palette: InfoPalette = .onDark

    @State private var width: CGFloat = 0
    /// Cached CoreText truncation, recomputed only when its inputs (width, value) change — not on every
    /// body evaluation (focus animations re-render the info columns repeatedly), so CTTypesetter work
    /// stays off the render path.
    @State private var wrapped: (body: AttributedString, truncated: Bool)?

    private var moreReserve: CGFloat { fontSize * 4 + 24 }
    private let lineSpacing: CGFloat = 4

    var body: some View {
        content
            .lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { _ in
                    Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                }
            }
            .onChange(of: width) { recomputeWrap() }
            .onChange(of: value) { recomputeWrap() }
    }

    /// Rebuilds the cached truncation for the current inputs. Cleared to `nil` when there's nothing to
    /// truncate (no line limit or no measured width yet), in which case `content` shows the full value.
    private func recomputeWrap() {
        guard let lineLimit, width > 1 else { wrapped = nil; return }
        wrapped = InfoTextWrap.truncate(value, fontSize: fontSize, width: width,
                                        lineLimit: lineLimit, reserve: moreReserve,
                                        palette: palette)
    }

    @ViewBuilder
    private var content: some View {
        if let wrapped, wrapped.truncated {
            Text(wrapped.body)   // pre-wrapped lines, the last ending with "…", + inline bold "MORE"
        } else {
            Text(value)
                .font(.system(size: fontSize))
                .foregroundStyle(palette.value)
                .lineLimit(lineLimit)
        }
    }
}

/// CoreText line-wrapping helper: breaks a string into rendered lines at a given width and, past a line
/// limit, builds an AttributedString of those lines whose last line ends with "…" followed by a bold
/// inline "MORE" cue. CoreText/Foundation only — no UIKit.
enum InfoTextWrap {
    private static func systemFont(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func lineBreaks(_ string: String, font: CTFont, width: CGFloat) -> [Int] {
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let attr = NSAttributedString(string: string, attributes: [key: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        let total = (string as NSString).length
        var breaks: [Int] = []
        var start = 0
        var guardCount = 0
        while start < total, guardCount < 400 {
            guardCount += 1
            let n = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if n <= 0 { break }
            start += n
            breaks.append(start)
        }
        return breaks
    }

    static func truncate(_ string: String, fontSize: CGFloat, width: CGFloat,
                         lineLimit: Int, reserve: CGFloat,
                         palette: InfoPalette = .onDark)
        -> (body: AttributedString, truncated: Bool) {
        guard width > 1, lineLimit >= 1 else { return (AttributedString(string), false) }
        let font = systemFont(fontSize)
        let ns = string as NSString
        let breaks = lineBreaks(string, font: font, width: width)
        if breaks.count <= lineLimit { return (AttributedString(string), false) }

        let starts = [0] + breaks
        var lines = (0..<(lineLimit - 1)).map { i in
            ns.substring(with: NSRange(location: starts[i], length: starts[i + 1] - starts[i]))
                .trimmingCharacters(in: .newlines)
        }
        // Break the remaining text at the reduced width so the last line leaves room for "MORE".
        let lastStart = starts[lineLimit - 1]
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let attr = NSAttributedString(string: string, attributes: [key: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        var n = CTTypesetterSuggestLineBreak(typesetter, lastStart, Double(max(10, width - reserve)))
        if n <= 0 { n = ns.length - lastStart }
        var last = ns.substring(with: NSRange(location: lastStart, length: n))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.hasSuffix("…") { last += "…" }
        lines.append(last)

        var body = AttributedString(lines.joined(separator: "\n") + " ")
        body.font = .system(size: fontSize)
        body.foregroundColor = palette.value
        var more = AttributedString("MORE")
        more.font = .system(size: fontSize, weight: .bold)
        more.foregroundColor = palette.more
        body += more
        return (body, true)
    }
}

/// An accessibility entry — an outlined badge (SDH / AD), styled like the hero metadata chips, above
/// its description.
struct AccessibilityItem: View {
    let badge: String
    let description: String
    var palette: InfoPalette = .onDark

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OutlinedBadge(text: badge, tint: palette.badge)
            Text(description)
                .font(.system(size: 23))
                .foregroundStyle(palette.accessory)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A focusable info column (Information / Languages / Accessibility). Plain text at rest, a card when
/// focused — but the button style is set ONCE and never swapped (tvOS drops focus the instant a focused
/// button's style changes, so a `.plain`↔`.card` swap makes the element un-focusable). Instead a single
/// style stays put and changes only its appearance on the element's own focus: nothing at rest, the
/// frosted card panel (the About card's look — 22 pt real padding, `.ultraThinMaterial`) plus the
/// native spring lift on focus. `spacing` sets the gap between items.
struct InfoColumnCard<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button { } label: {
            CardLabel(spacing: spacing, content: content)
        }
        .buttonStyle(CardFocusStyle())
    }

    /// Reads the button's focus from the environment so the frosted panel only shows while focused. The
    /// padding is constant regardless, so the text doesn't shift as focus moves between columns.
    private struct CardLabel<C: View>: View {
        let spacing: CGFloat
        @ViewBuilder var content: () -> C
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedInfoCard(padding: 22, bleedLeading: false, showsBackground: isFocused)
            // Same spring as CardFocusStyle's lift, so the frosted panel crossfades in step with the
            // scale rather than popping — the two together read as one native card focus.
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isFocused)
        }
    }
}

