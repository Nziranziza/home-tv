import SwiftUI

/// "Choose a Version" — a master–detail stream browser modeled on Apple TV's detail
/// language. The left column filters streams by **provider** and **quality** (frosted
/// segmented controls) over a list grouped into quality sections; the right column is a
/// frosted detail panel that *reflects the focused stream* (per Apple's "direct and reflect
/// focus" pattern) showing full specs and the primary Play action. Everything floats over a
/// blurred still of the title's own artwork.
struct StreamPickerView: View {
    let type: String
    let contentID: String
    let title: String
    /// Artwork for the cinematic backdrop / title logo, passed from the screen that launched
    /// playback. Nil falls back to a near-black backdrop / text title.
    var backgroundURL: String? = nil
    var logoURL: String? = nil

    @State private var registry = AddonRegistry.shared
    @State private var preference = PlayerPreference.shared
    @State private var streams: [LabeledStream] = []
    @State private var status: LoadStatus = .loading
    @State private var errorMessage: String?

    /// The two filter axes. "All" is the aggregate option for each.
    @State private var selectedProvider: String = "All"
    @State private var selectedQuality: String = "All"
    /// Id of the stream mirrored in the detail panel. Tracks the focused row; falls back to
    /// the first stream in the current filter when nil or filtered away.
    @State private var detailID: String?

    @FocusState private var focus: PickerFocus?
    @Namespace private var pickerScope
    @Namespace private var statusScope
    /// One-shot guard so initial focus is placed on the first stream exactly once after load.
    @State private var didPlaceInitialFocus = false
    /// Drives the loading-skeleton pulse (single source so all placeholders breathe in sync).
    @State private var skeletonPulse = false

    @Environment(\.dismiss) private var dismiss

    static let allLabel = "All"

    enum LoadStatus { case loading, loaded, empty, failed }

    enum PickerFocus: Hashable {
        case provider(String)
        case quality(String)
        case stream(String)
        case play
        case retry
        case close
    }

    struct LabeledStream: Identifiable {
        let stream: Stream
        let addonName: String
        let meta: StreamMeta
        var id: String { "\(addonName):\(stream.id)" }
    }

    // Header geometry, shared so the content's top inset always reserves exactly the header's
    // space. The header is pinned to the top independent of content, so it never shifts between
    // the loading, loaded, and empty/error states.
    private static let headerTopPadding: CGFloat = 72
    private static let headerSlotHeight: CGFloat = 110
    private static let headerGap: CGFloat = 34
    private static var contentTopInset: CGFloat { headerTopPadding + headerSlotHeight + headerGap }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Color.background.ignoresSafeArea()
            backdrop

            // Content fills the area below the reserved header space.
            // `ignoresSafeArea` keeps positioning in screen coordinates so the header sits at the
            // same place whether or not the current state contains a ScrollView (a ScrollView
            // otherwise consumes the top safe-area inset, shifting everything ~54pt vs the
            // no-stream/loading states which don't have one).
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 88)
                .padding(.top, Self.contentTopInset)
                .padding(.bottom, 72)
                .ignoresSafeArea()

            // Header pinned to the top — its position does not depend on the content state.
            headerBar
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 88)
                .padding(.top, Self.headerTopPadding)
                .ignoresSafeArea()

            if let errorMessage {
                errorToast(errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: errorMessage) {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { self.errorMessage = nil }
                    }
            }
        }
        .task(id: contentID) { await load() }
        // Detail panel reflects the focused stream.
        .onChange(of: focus) { _, newValue in
            if case .stream(let id) = newValue { detailID = id }
        }
        // When a filter changes, the visible set changes; reset the detail to the new first row.
        .onChange(of: selectedProvider) { _, _ in
            if !qualities.contains(selectedQuality) { selectedQuality = Self.allLabel }
            detailID = nil
        }
        .onChange(of: selectedQuality) { _, _ in detailID = nil }
    }

    // MARK: - Backdrop

    /// Blurred, dimmed still of the title's own artwork filling the screen — the picker floats
    /// over the content the user is choosing a stream for. The image is almost always already
    /// in `ImageLoader`'s cache from the hero/detail screen.
    private var backdrop: some View {
        GeometryReader { geo in
            // Decode + blur at 1/8 scale, then upscale — a 60pt blur over a full-screen image is an
            // expensive GPU pass that hitches when the picker appears. The heavy blur destroys detail, so
            // the small-raster result is visually identical (same trick as `DetailBackdropBlurredImage`).
            let downscale: CGFloat = 8
            RemoteImage(
                url: backgroundURL.flatMap(URL.init(string:)),
                targetSize: CGSize(width: geo.size.width / downscale, height: geo.size.height / downscale),
                contentMode: .fill
            ) {
                Color(white: 0.05)
            }
            .frame(width: geo.size.width / downscale, height: geo.size.height / downscale)
            .blur(radius: 60 / downscale)
            .scaleEffect(downscale * 1.5)                                    // upscale to fill + the original 1.5 overscale
            .frame(width: geo.size.width, height: geo.size.height)          // reset layout size so the scrim/clip cover the screen
            .overlay(backdropScrim)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var backdropScrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0.0),
                    .init(color: .black.opacity(0.78), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.6)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 24) {
            header
            Spacer(minLength: 24)
            // Same circular button as the hero / detail screens.
            HeroCircleButton(icon: "xmark", accessibilityLabel: "Close") { dismiss() }
                .focused($focus, equals: .close)
        }
        .focusSection()
    }

    /// Switches the content below the pinned header. Each branch fills the content area, so the
    /// header above never moves.
    @ViewBuilder
    private var contentArea: some View {
        switch status {
        case .empty, .failed:
            statusView
        case .loading, .loaded:
            streamColumns
        }
    }

    // Fixed-height title slot so a logo image (real data) and the text fallback occupy the same
    // height — the header never reflows when the logo loads or the title changes.
    private var header: some View {
        titleView
            .frame(height: Self.headerSlotHeight, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var titleView: some View {
        if let url = logoURL.flatMap(URL.init(string:)) {
            RemoteImage(
                url: url,
                targetSize: CGSize(width: 800, height: 200),
                contentMode: .fit
            ) {
                titleText
            }
            .frame(maxWidth: 620, maxHeight: 120, alignment: .bottomLeading)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .accessibilityLabel(title)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 52, weight: .bold))
            .foregroundStyle(Theme.Color.primaryText)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    // MARK: - Filter axes

    /// Pure filtering/grouping logic, built from the current state on each access. The view keeps
    /// owning all of its `@State`; this holds no state of its own (see `StreamPickerViewModel`).
    private var model: StreamPickerViewModel {
        StreamPickerViewModel(
            streams: streams,
            selectedProvider: selectedProvider,
            selectedQuality: selectedQuality,
            detailID: detailID
        )
    }

    /// "All" + distinct provider names in load order.
    private var providers: [String] { model.providers }
    private var providerStreams: [LabeledStream] { model.providerStreams }
    /// "All" + the quality buckets present for the selected provider, high → low.
    private var qualities: [String] { model.qualities }
    private var filteredStreams: [LabeledStream] { model.filteredStreams }
    /// Filtered streams grouped into quality sections, high → low.
    private var qualitySections: [(quality: String, items: [LabeledStream])] { model.qualitySections }
    private var firstStreamID: String? { model.firstStreamID }
    private var detailStream: LabeledStream? { model.detailStream }

    // MARK: - Browser (master + detail)

    /// Shared two-column container used for BOTH the loading and loaded states. The outer HStack,
    /// its frames, spacing, and the per-column frames are identical in both states — only the leaf
    /// content (real vs skeleton) swaps inside each column. This guarantees the header / close
    /// button (and everything else) don't shift when the skeleton is replaced by content.
    private var streamColumns: some View {
        HStack(alignment: .top, spacing: 44) {
            Group {
                if status == .loaded { masterColumn } else { masterSkeleton }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Group {
                if status == .loaded { detailPanel } else { detailSkeleton }
            }
            .frame(width: 560)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusScope(pickerScope)
        // LazyVStack rows aren't realized when the engine first resolves default focus, so it
        // lands on the Source control. Once loaded, nudge focus onto the first stream — the
        // primary content — matching the tvOS guideline to focus the primary action.
        .task(id: status) {
            guard status == .loaded, !didPlaceInitialFocus, let id = firstStreamID else { return }
            didPlaceInitialFocus = true
            try? await Task.sleep(for: .milliseconds(60))
            focus = .stream(id)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                skeletonPulse = true
            }
        }
    }

    private var masterColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            SegmentedControl(
                label: "Source",
                options: providers,
                selected: selectedProvider,
                focus: $focus,
                focusCase: PickerFocus.provider,
                onSelect: { selectedProvider = $0 }
            )
            if qualities.count > 2 {
                SegmentedControl(
                    label: "Quality",
                    options: qualities,
                    selected: selectedQuality,
                    focus: $focus,
                    focusCase: PickerFocus.quality,
                    onSelect: { selectedQuality = $0 }
                )
            }
            streamList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var streamList: some View {
        // Build the filter/group model ONCE for the whole list, then read its stored fields — instead of
        // each row rebuilding it via `firstStreamID` (which was O(n²) across the list on every focus move).
        let model = self.model
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if model.filteredStreams.isEmpty {
                    inlineEmpty("No streams at this quality.")
                } else {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(model.qualitySections, id: \.quality) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(section.quality, count: section.items.count)
                                ForEach(section.items) { item in
                                    streamRowButton(item, firstStreamID: model.firstStreamID)
                                }
                            }
                        }
                    }
                    // Trailing inset keeps the lifted focused card clear of the detail panel.
                    .padding(.top, 8)
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
            // The system `.card` style lifts/scales the focused row, so the scroll bounds must
            // not clip it — but with clipping fully off, rows scrolled up bleed over the filter
            // controls above. The mask re-clips the TOP only (overflow there hides under the
            // controls) while extending left/right/bottom so the focus lift still shows.
            .scrollClipDisabled()
            .mask {
                Rectangle().padding([.horizontal, .bottom], -160)
            }
            .onChange(of: selectedProvider) { _, _ in scrollToTop(proxy) }
            .onChange(of: selectedQuality) { _, _ in scrollToTop(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
    }

    private func streamRowButton(_ item: LabeledStream, firstStreamID: String?) -> some View {
        Button {
            Task { await play(item.stream) }
        } label: {
            streamRow(item, isFocused: focus == .stream(item.id))
        }
        .buttonStyle(.card)
        .focused($focus, equals: .stream(item.id))
        .id(item.id)
        .prefersDefaultFocus(item.id == firstStreamID, in: pickerScope)
    }

    private func sectionHeader(_ quality: String, count: Int) -> some View {
        HStack(spacing: 14) {
            qualityBadge(quality)
            Text(count == 1 ? "1 stream" : "\(count) streams")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.Color.tertiaryText)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// A list row: release name + a compact spec sub-line, with a delivery glyph that becomes a
    /// play glyph on focus. Minimal — the full picture lives in the detail panel.
    private func streamRow(_ item: LabeledStream, isFocused: Bool) -> some View {
        let m = item.meta
        var sub: [String] = []
        if let codec = m.codec { sub.append(codec) }
        if let audio = m.audio { sub.append(audio) }
        if let size = m.size { sub.append(size) }
        if selectedProvider == Self.allLabel { sub.append(item.addonName) }

        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(m.releaseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if let debrid = m.debrid {
                        DebridBadge(info: debrid)
                    }
                    if m.sourceIsWarning, let tag = m.sourceTag {
                        Text(tag).foregroundStyle(Theme.Color.destructive)
                        Text("·").foregroundStyle(Theme.Color.tertiaryText)
                    } else if let tag = m.sourceTag {
                        Text(tag)
                        Text("·").foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Text(sub.joined(separator: " · "))
                }
                .font(.callout)
                .foregroundStyle(Theme.Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: deliveryGlyph(item, isFocused: isFocused))
                .font(.title3.weight(.semibold))
                .foregroundStyle(isFocused ? Theme.Color.primaryText : Theme.Color.tertiaryText)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The trailing glyph: play on focus, otherwise a bolt for a cached debrid stream (instant), a
    /// download arrow for one that must be fetched (or a plain torrent), and a globe for a direct URL.
    private func deliveryGlyph(_ item: LabeledStream, isFocused: Bool) -> String {
        if isFocused { return "play.fill" }
        if let debrid = item.meta.debrid { return debrid.isCached ? "bolt.fill" : "arrow.down.to.line" }
        return item.stream.infoHash != nil ? "arrow.down.to.line" : "globe"
    }

    // MARK: - Detail panel (reflects the focused stream)

    @ViewBuilder
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let item = detailStream {
                let m = item.meta
                // The whole header block (eyebrow + resolution/HDR headline + release name) is a
                // SINGLE fixed-height container. This guarantees the spec rows and Play button
                // below never move as focus shifts between streams — regardless of whether the
                // headline has an HDR tag or the release name is 1 vs 3 lines. A fixed frame is
                // bulletproof across tvOS versions (unlike `reservesSpace`).
                VStack(alignment: .leading, spacing: 10) {
                    Text("STREAM DETAILS")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.Color.tertiaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(m.resolution)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(qualityColor(m.resolution))
                            .lineLimit(1)
                        if let hdr = m.hdr {
                            Text(hdr == "DV" ? "Dolby Vision" : "HDR")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(hdrColor(hdr))
                                .lineLimit(1)
                        }
                    }
                    Text(m.releaseName)
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .frame(height: 184, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    specRow("Video", videoSpec(m))
                    specRow("Audio", m.audio ?? "—")
                    specRow("Source", m.sourceTag ?? "—", warning: m.sourceIsWarning, last: false)
                    specRow("File Size", m.size ?? "Unknown")
                    specRow("Delivery", item.stream.infoHash != nil ? "Torrent" : "Direct")
                    // Always rendered (with a — fallback) so the spec block keeps a constant height
                    // as focus moves between debrid and non-debrid streams — otherwise the Play
                    // button below would jump by one row.
                    specRow(
                        "Debrid",
                        m.debrid.map { "\($0.service) · \($0.isCached ? "Cached" : "Download")" } ?? "—",
                        valueColor: m.debrid.map { $0.isCached ? DebridBadge.cachedColor : DebridBadge.downloadColor }
                    )
                    specRow("Provider", item.addonName, last: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 12) {
                    HeroPlayButton(title: "Play", icon: "play.fill") {
                        Task { await play(item.stream) }
                    }
                    .focused($focus, equals: .play)
                    Text("Opens in \(preference.defaultPlayer.displayName)")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .focusSection()
    }

    private func videoSpec(_ m: StreamMeta) -> String { model.videoSpec(m) }

    private func specRow(_ label: String, _ value: String, warning: Bool = false, valueColor: Color? = nil, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(Theme.Color.tertiaryText)
                Spacer(minLength: 16)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(valueColor ?? (warning ? Theme.Color.destructive : Theme.Color.primaryText))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 11)
            if !last {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Badges & colors

    private func qualityBadge(_ label: String) -> some View {
        let color = qualityColor(label)
        return Text(label)
            .font(.title3.weight(.heavy))
            .foregroundStyle(color)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
    }

    private func hdrColor(_ label: String) -> Color {
        switch label {
        case "DV": return Color(hue: 0.13, saturation: 0.95, brightness: 0.98) // Dolby Vision gold
        default: return Color(hue: 0.07, saturation: 0.85, brightness: 0.97)   // HDR amber
        }
    }

    private func qualityColor(_ label: String) -> Color {
        switch label {
        case "4K": return Color(hue: 0.55, saturation: 0.7, brightness: 0.95)
        case "1080p": return Color(hue: 0.33, saturation: 0.55, brightness: 0.85)
        case "720p": return Color(hue: 0.13, saturation: 0.65, brightness: 0.92)
        case "480p", "SD": return Color(hue: 0.05, saturation: 0.65, brightness: 0.9)
        default: return Theme.Color.primaryText.opacity(0.85)
        }
    }

    // MARK: - Status view (no streams / can't reach add-ons / no add-ons)

    /// A premium empty/error state: a frosted icon badge, a bold title, a supporting line, and a
    /// "Try Again" action where retrying makes sense. Messaging adapts to the actual situation.
    @ViewBuilder
    private var statusView: some View {
        let info = statusInfo
        VStack(spacing: 30) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1)
                Image(systemName: info.icon)
                    .font(.system(size: 62, weight: .regular))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .frame(width: 168, height: 168)

            VStack(spacing: 14) {
                Text(info.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(info.message)
                    .font(.title3)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 660)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if info.showsRetry {
                HeroPlayButton(title: "Try Again", icon: "arrow.clockwise") { retry() }
                    .focused($focus, equals: .retry)
                    .prefersDefaultFocus(in: statusScope)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .focusScope(statusScope)
    }

    /// Icon / title / message / retry, tailored to why there's nothing to show.
    private var statusInfo: (icon: String, title: String, message: String, showsRetry: Bool) {
        if status == .failed {
            return ("antenna.radiowaves.left.and.right.slash",
                    "Can’t Reach Add-ons",
                    "We couldn’t load streams from your add-ons. Check your connection and try again.",
                    true)
        }
        if registry.enabledAddons.isEmpty {
            return ("puzzlepiece.extension",
                    "No Add-ons Installed",
                    "Add a streaming add-on in Settings to start finding streams for your library.",
                    false)
        }
        // Add-ons are installed, but none of them actually provide streams (e.g. only a metadata
        // add-on like Cinemeta) — retrying won't help, so guide the user to Settings instead.
        if !hasStreamAddon {
            return ("puzzlepiece.extension",
                    "No Streaming Add-ons",
                    "Your installed add-ons only provide metadata. Add a streaming add-on (such as Torrentio) in Settings to find streams.",
                    false)
        }
        return ("magnifyingglass",
                "No Streams Found",
                "There aren’t any playable streams for this title yet. Check back later or try again.",
                true)
    }

    /// True when at least one enabled add-on declares the Stremio `stream` resource. Metadata-only
    /// add-ons (e.g. Cinemeta) don't, so a library with only those can never return streams.
    private var hasStreamAddon: Bool {
        registry.enabledAddons.contains { addon in
            (addon.manifest.resources ?? []).contains { $0.name == "stream" }
        }
    }

    private func retry() {
        Task { await load() }
    }

    // MARK: - Loading skeleton

    /// Left-column placeholder, mirroring `masterColumn` (two filter bars + grouped rows). The
    /// shared `streamColumns` container provides the fill frame, so this matches the loaded master
    /// column's geometry exactly. Pulses via the shared `skeletonPulse`.
    private var masterSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            skel(420, 52, radius: Theme.Radius.pill)   // Source control
            skel(360, 52, radius: Theme.Radius.pill)   // Quality control
            VStack(alignment: .leading, spacing: 22) {
                skeletonSection(rows: 2)
                skeletonSection(rows: 3)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }

    private func skeletonSection(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                skel(72, 36, radius: 18)
                skel(120, 18, radius: 9)
            }
            ForEach(0..<rows, id: \.self) { _ in skeletonRow }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                skel(380, 22, radius: 11)
                skel(240, 16, radius: 8)
            }
            Spacer(minLength: 0)
            skel(28, 28, radius: 14)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var detailSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                skel(140, 14, radius: 7)
                skel(240, 38, radius: 10)
                VStack(alignment: .leading, spacing: 10) {
                    skel(440, 16, radius: 8)
                    skel(390, 16, radius: 8)
                    skel(300, 16, radius: 8)
                }
            }
            VStack(spacing: 26) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack {
                        skel(120, 16, radius: 8)
                        Spacer(minLength: 0)
                        skel(150, 16, radius: 8)
                    }
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            skel(180, 60, radius: 30)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// One skeleton block: a rounded placeholder that pulses with the shared `skeletonPulse`.
    private func skel(_ width: CGFloat, _ height: CGFloat, radius: CGFloat = 8) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: width, height: height)
            .opacity(skeletonPulse ? 1.0 : 0.45)
    }

    private func inlineEmpty(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 44))
            Text(message)
                .font(.title3)
        }
        .foregroundStyle(Theme.Color.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 60)
    }

    private func errorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.Color.destructive.opacity(0.92)))
                .padding(.bottom, 60)
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = firstStreamID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(first, anchor: .top)
        }
    }

    // MARK: - Data

    private func load() async {
        status = .loading
        streams = []

        if ProcessInfo.processInfo.environment["MOCK_STREAMS"] == "1" {
            streams = sampleStreams()
            status = .loaded
            return
        }

        let addons = registry.enabledAddons

        let results = await withTaskGroup(of: (String, [Stream])?.self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        let resp = try await StremioClient.shared.streams(
                            baseURL: addon.baseURL,
                            type: type,
                            id: contentID
                        )
                        return (addon.manifest.name, resp.streams)
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [(String, [Stream])] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        if results.isEmpty {
            status = addons.isEmpty ? .empty : .failed
            return
        }

        let labeled = results.flatMap { addonName, streams in
            streams.map { LabeledStream(stream: $0, addonName: addonName, meta: StreamMeta.make(from: $0)) }
        }

        streams = labeled.sorted { $0.meta.resolutionRank > $1.meta.resolutionRank }
        status = streams.isEmpty ? .empty : .loaded
    }

    private func sampleStreams() -> [LabeledStream] {
        // `debrid` is the tag a debrid-enabled add-on prefixes onto the stream name: [RD+]/[AD+]
        // (cached, instant) or [RD download] (must be fetched first). nil = a plain torrent/direct.
        let samples: [(addon: String, title: String, hash: String?, url: String?, debrid: String?)] = [
            ("Torrentio TB", "Obsession.2026.2160p.UHD.WEB-DL.DV.HDR10Plus.HEVC.Atmos.TrueHD.7.1.MULTi.ENG.FRA.GER.ITA.SPA.JPN-FLUX 62.4 GB", "abc123hash", nil, "[RD+]"),
            ("Torrentio TB", "Obsession.2026.REMUX.2160p.UHD.BluRay.HDR.TrueHD.7.1.x265-GROUP 48.1 GB", "def456hash", nil, "[RD+]"),
            ("Torrentio TB", "Obsession.2026.1080p.BluRay.x265.10bit.DTS-HD-RARBG 8.1 GB", "ghi789hash", nil, "[RD download]"),
            ("Torrentio TB", "Obsession.2026.1080p.WEB-DL.DDP5.1.H.264-NTb 4.7 GB", "jkl012hash", nil, "[AD+]"),
            ("Torrentio TB", "Obsession.2026.720p.WEB-DL.AAC.H.264 1.9 GB", "stu678hash", nil, nil),
            ("Torrentio TB", "Obsession.2026.1080p.CAMRip.LAT.ENG.DUB.1XBET.mp4 3.15 GB", "mno345hash", nil, nil),
            ("Public Domain Movies", "Obsession.2026.1080p.H.264.AAC 2.6 GB", nil, "https://archive.org/sample/1080.mp4", nil),
            ("Public Domain Movies", "Obsession 720p 1.3 GB", nil, "https://archive.org/sample/720.mp4", nil)
        ]
        return samples.map { sample in
            let stream = Stream(
                name: sample.debrid.map { "\($0) \(sample.addon)" } ?? sample.addon,
                title: sample.title,
                description: nil,
                url: sample.url,
                ytId: nil,
                infoHash: sample.hash,
                fileIdx: nil,
                sources: nil,
                behaviorHints: nil
            )
            return LabeledStream(stream: stream, addonName: sample.addon, meta: StreamMeta.make(from: stream))
        }
    }

    nonisolated static func qualityRank(_ label: String) -> Int {
        switch label {
        case "4K": 5
        case "1080p": 4
        case "720p": 3
        case "480p", "SD": 2
        case "AUTO": 1
        default: 0
        }
    }

    private func play(_ stream: Stream) async {
        do {
            try await PlayerLauncher.play(
                stream,
                using: preference.defaultPlayer,
                title: title
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

