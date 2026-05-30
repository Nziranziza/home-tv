import SwiftUI

struct StreamPickerView: View {
    let type: String
    let contentID: String
    let title: String

    @State private var registry = AddonRegistry.shared
    @State private var preference = PlayerPreference.shared
    @State private var streams: [LabeledStream] = []
    @State private var status: LoadStatus = .loading
    @State private var errorMessage: String?

    /// The two filter axes. "All" is the aggregate option for each.
    @State private var selectedAddon: String = "All"
    @State private var selectedResolution: String = "All"

    /// Single source of truth for what's focused across all three regions. Moving
    /// focus onto an addon/resolution drives the filter (live-filter-on-focus).
    @FocusState private var focus: PickerFocus?
    @Namespace private var dashboardNamespace

    @Environment(\.dismiss) private var dismiss

    static let allLabel = "All"

    enum LoadStatus { case loading, loaded, empty, failed }

    enum PickerFocus: Hashable {
        case addon(String)
        case resolution(String)
        case stream(String)
        case close
    }

    struct LabeledStream: Identifiable {
        let stream: Stream
        let addonName: String
        let meta: StreamMeta
        var id: String { "\(addonName):\(stream.id)" }
    }

    /// Everything we parse out of a stream's title/name/description. Computed
    /// ONCE at load time (see `make(from:)`) so filtering and row rendering read
    /// plain stored fields instead of re-running regex on every focus move.
    struct StreamMeta: Hashable {
        let resolution: String
        let resolutionRank: Int
        let hdr: String?
        let codec: String?
        let sourceTag: String?
        let sourceIsWarning: Bool
        let size: String?
        let releaseName: String

        static func make(from stream: Stream) -> StreamMeta {
            let haystack = "\(stream.title ?? "") \(stream.name ?? "") \(stream.description ?? "")"
            func matches(_ pattern: String) -> Bool {
                haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }

            let resolution: String
            if matches(#"\b(4K|2160p|UHD)\b"#) { resolution = "4K" }
            else if matches(#"\b1080p\b"#) { resolution = "1080p" }
            else if matches(#"\b720p\b"#) { resolution = "720p" }
            else if matches(#"\b480p\b"#) { resolution = "480p" }
            else if matches(#"\b(SD|CAM|TS)\b"#) { resolution = "SD" }
            else { resolution = "AUTO" }

            let hdr: String?
            if haystack.localizedCaseInsensitiveContains("DV") || haystack.localizedCaseInsensitiveContains("Dolby Vision") {
                hdr = "DV"
            } else if haystack.localizedCaseInsensitiveContains("HDR") {
                hdr = "HDR"
            } else {
                hdr = nil
            }

            let codec: String?
            if matches(#"\bav1\b"#) { codec = "AV1" }
            else if matches(#"\b(x265|h\.?265|hevc)\b"#) { codec = "HEVC" }
            else if matches(#"\b(x264|h\.?264|avc)\b"#) { codec = "H.264" }
            else { codec = nil }

            // CAM-type rips flagged as a warning so they're easy to avoid.
            let sourceTag: String?
            let sourceIsWarning: Bool
            if matches(#"\b(cam|camrip|hdcam|ts|telesync|hdts)\b"#) { sourceTag = "CAM"; sourceIsWarning = true }
            else if matches(#"\bremux\b"#) { sourceTag = "REMUX"; sourceIsWarning = false }
            else if matches(#"\b(blu-?ray|bdrip|brrip|bd)\b"#) { sourceTag = "BluRay"; sourceIsWarning = false }
            else if matches(#"\bweb-?dl\b"#) { sourceTag = "WEB-DL"; sourceIsWarning = false }
            else if matches(#"\b(webrip|web)\b"#) { sourceTag = "WEB"; sourceIsWarning = false }
            else { sourceTag = nil; sourceIsWarning = false }

            let size: String?
            let sizeHaystack = "\(stream.title ?? "") \(stream.description ?? "")"
            if let range = sizeHaystack.range(of: #"(\d+(?:\.\d+)?)\s?(GB|MB|TB)"#, options: [.regularExpression, .caseInsensitive]) {
                size = String(sizeHaystack[range])
            } else {
                size = nil
            }

            // Torrentio packs name + seeders + size across several lines (often
            // with emoji); keep just the first non-empty line as the title.
            let source = stream.title ?? stream.name ?? "Stream"
            let releaseName = source
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? "Stream"

            return StreamMeta(
                resolution: resolution,
                resolutionRank: StreamPickerView.qualityRank(resolution),
                hdr: hdr,
                codec: codec,
                sourceTag: sourceTag,
                sourceIsWarning: sourceIsWarning,
                size: size,
                releaseName: releaseName
            )
        }
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                headerBar
                switch status {
                case .loading:
                    loadingView.padding(.vertical, 60)
                case .empty:
                    placeholder(icon: "exclamationmark.triangle",
                                message: "No streams found.")
                case .failed:
                    placeholder(icon: "wifi.exclamationmark",
                                message: "Couldn't reach any addon.")
                case .loaded:
                    dashboard
                }
            }
            .padding(.horizontal, 88)
            .padding(.top, 80)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let errorMessage {
                errorToast(errorMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: errorMessage) {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { self.errorMessage = nil }
                    }
            }
        }
        .task(id: contentID) { await load() }
        // Live filter: focusing a tab/resolution updates the selection. One
        // direction only — selection changes must never write back to `focus`
        // (except the deliberate reset below) or this loops.
        .onChange(of: focus) { _, newValue in
            switch newValue {
            case .addon(let name): selectedAddon = name
            case .resolution(let label): selectedResolution = label
            case .stream, .close, .none: break
            }
        }
        // When the addon changes, the resolution list is recomputed; drop a
        // now-absent resolution back to "All".
        .onChange(of: selectedAddon) { _, _ in
            if !resolutions.contains(selectedResolution) {
                selectedResolution = Self.allLabel
            }
        }
    }

    /// Title block + close button live in the same row, so the close button is
    /// part of the natural focus order (Up from the list lands on it, Down
    /// returns to the list). Pinning it in a corner trapped focus instead.
    private var headerBar: some View {
        HStack(alignment: .top, spacing: 24) {
            header
            Spacer(minLength: 24)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(CircularIconButtonStyle())
            .focused($focus, equals: .close)
        }
        // The close button is the only focusable up here and sits far right of
        // the tabs; a focus section lets Up from the tab bar jump to it
        // regardless of horizontal alignment.
        .focusSection()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT A STREAM")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.Color.primaryText.opacity(0.92))
                .tracking(1.5)
            Text(title)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(2)
            Text("Opens in \(preference.defaultPlayer.displayName)")
                .font(.callout)
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    // MARK: - Dashboard

    /// "All" + distinct addon names in the order they were loaded.
    private var addonTabs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in streams where !seen.contains(item.addonName) {
            seen.insert(item.addonName)
            ordered.append(item.addonName)
        }
        return [Self.allLabel] + ordered
    }

    /// Streams for the selected addon ("All" => everything).
    private var addonStreams: [LabeledStream] {
        guard selectedAddon != Self.allLabel else { return streams }
        return streams.filter { $0.addonName == selectedAddon }
    }

    /// "All" + the resolution buckets actually present for the selected addon,
    /// ordered high → low. Reads precomputed `meta` — no regex.
    private var resolutions: [String] {
        let buckets = Set(addonStreams.map { $0.meta.resolution })
        let ordered = buckets.sorted { Self.qualityRank($0) > Self.qualityRank($1) }
        return [Self.allLabel] + ordered
    }

    /// Final list shown in the middle, filtered by both axes. `streams` is
    /// already quality-sorted by `load()`, so order is preserved.
    private var filteredStreams: [LabeledStream] {
        guard selectedResolution != Self.allLabel else { return addonStreams }
        return addonStreams.filter { $0.meta.resolution == selectedResolution }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 28) {
            addonTabBar
            HStack(alignment: .top, spacing: 48) {
                resolutionColumn
                streamColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusScope(dashboardNamespace)
    }

    /// TOP: horizontal addon tabs. A plain HStack of buttons (mirrors the season
    /// selector in MetaDetailView) — left/right traverse natively. A ScrollView
    /// or focusSection here breaks tab-to-tab navigation on tvOS.
    private var addonTabBar: some View {
        HStack(spacing: 12) {
            ForEach(addonTabs, id: \.self) { name in
                Button { selectedAddon = name } label: {
                    Text(name).fixedSize()
                }
                .buttonStyle(DashboardTabStyle(isSelected: selectedAddon == name))
                .focused($focus, equals: .addon(name))
            }
        }
        .padding(.vertical, 4)
    }

    /// LEFT: vertical resolution list, fixed-width column.
    private var resolutionColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(resolutions, id: \.self) { res in
                Button { selectedResolution = res } label: {
                    Text(res).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(DashboardTabStyle(isSelected: selectedResolution == res, fillsWidth: true))
                .focused($focus, equals: .resolution(res))
            }
        }
        .frame(width: 220, alignment: .leading)
        .focusSection()
    }

    /// MIDDLE: the filtered stream list. Only this column scrolls vertically, and
    /// it fills the height below the tabs. `LazyVStack` builds only visible rows.
    private var streamColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if filteredStreams.isEmpty {
                    inlineEmpty("No streams at this quality.")
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(filteredStreams.enumerated()), id: \.element.id) { index, item in
                            Button {
                                Task { await play(item) }
                            } label: {
                                streamRow(item)
                            }
                            .buttonStyle(StreamCardStyle())
                            .focused($focus, equals: .stream(item.id))
                            .id(item.id)
                            .prefersDefaultFocus(index == 0, in: dashboardNamespace)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .onChange(of: selectedAddon) { _, _ in scrollToTop(proxy) }
            .onChange(of: selectedResolution) { _, _ in scrollToTop(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = filteredStreams.first else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(first.id, anchor: .top)
        }
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
        .padding(.vertical, 40)
    }

    /// Title on its own line, a rail of metadata chips beneath. Nothing is
    /// width-constrained against the title, so chips never overlap it. Reads the
    /// precomputed `meta` — no regex during rendering.
    private func streamRow(_ item: LabeledStream) -> some View {
        let meta = item.meta
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(meta.releaseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: item.stream.infoHash != nil ? "link" : "globe")
                    .font(.title3)
                    .foregroundStyle(Theme.Color.tertiaryText)
            }

            HStack(spacing: 10) {
                resolutionChip(meta.resolution)

                if let hdr = meta.hdr {
                    solidChip(hdr, fill: hdrColor(hdr))
                }
                if let codec = meta.codec {
                    outlineChip(codec)
                }
                if let tag = meta.sourceTag {
                    outlineChip(tag, tint: meta.sourceIsWarning ? Theme.Color.destructive : Theme.Color.secondaryText)
                }

                metaSummary(for: item)
                    .layoutPriority(-1)
            }
        }
    }

    /// The headline quality pill — color-coded by resolution, sized to its text.
    private func resolutionChip(_ label: String) -> some View {
        let color = qualityColor(label)
        return Text(label)
            .font(.callout.weight(.heavy))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
    }

    private func solidChip(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }

    private func outlineChip(_ text: String, tint: Color = Theme.Color.secondaryText) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(tint.opacity(0.32), lineWidth: 1))
    }

    /// Addon · size · Magnet, trailing the chips. Truncates before it can push
    /// the chips around.
    private func metaSummary(for item: LabeledStream) -> some View {
        var parts: [String] = [item.addonName]
        if let size = item.meta.size { parts.append(size) }
        if item.stream.infoHash != nil { parts.append("Magnet") }
        return Text(parts.joined(separator: "  •  "))
            .font(.callout)
            .foregroundStyle(Theme.Color.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 4)
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large)
            Text("Searching addons…")
                .font(.title3)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func placeholder(icon: String, message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 60))
            Text(message)
                .font(.title2)
        }
        .foregroundStyle(Theme.Color.tertiaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func errorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.Color.destructive.opacity(0.9)))
                .padding(.bottom, 60)
        }
    }

    private func hdrColor(_ label: String) -> Color {
        switch label {
        case "DV": return Color(hue: 0.13, saturation: 0.95, brightness: 0.98) // Dolby Vision gold
        default: return Color(hue: 0.07, saturation: 0.85, brightness: 0.97)   // HDR amber/orange
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
        let samples: [(String, String, String?, String?)] = [
            ("Torrentio TB", "Obsession.2026.2160p.WEB-DL.DV.HDR10Plus.HEVC.DDP5.1-FLUX 62.4 GB", "abc123hash", nil),
            ("Torrentio TB", "Obsession.2026.REMUX.2160p.UHD.BluRay.HDR.x265-GROUP 48.1 GB", "def456hash", nil),
            ("Torrentio TB", "Obsession.2026.1080p.BluRay.x265.10bit-RARBG 8.1 GB", "ghi789hash", nil),
            ("Torrentio TB", "Obsession.2026.1080p.WEB-DL.H.264-NTb 4.7 GB", "jkl012hash", nil),
            ("Torrentio TB", "Obsession.2026.1080p.CAMRip.LAT.ENG.DUB.1XBET.mp4 3.15 GB", "mno345hash", nil),
            ("Public Domain Movies", "Obsession.2026.720p.H.264 1.3 GB", nil, "https://archive.org/sample/720.mp4")
        ]
        return samples.map { sample in
            let (addon, title, hash, url) = sample
            let stream = Stream(
                name: addon,
                title: title,
                description: nil,
                url: url,
                ytId: nil,
                infoHash: hash,
                fileIdx: nil,
                sources: nil,
                behaviorHints: nil
            )
            return LabeledStream(stream: stream, addonName: addon, meta: StreamMeta.make(from: stream))
        }
    }

    static func qualityRank(_ label: String) -> Int {
        switch label {
        case "4K": 5
        case "1080p": 4
        case "720p": 3
        case "480p", "SD": 2
        case "AUTO": 1
        default: 0
        }
    }

    private func play(_ item: LabeledStream) async {
        do {
            try await PlayerLauncher.play(
                item.stream,
                using: preference.defaultPlayer,
                title: title
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Tab/row style shared by the addon tabs and the resolution list. Mirrors the
/// season selector elsewhere in the app: focused = solid white fill + black
/// text; selected-but-unfocused = translucent white; otherwise gray. Set
/// `fillsWidth` for the left-aligned resolution rows.
private struct DashboardTabStyle: ButtonStyle {
    let isSelected: Bool
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isSelected: isSelected, fillsWidth: fillsWidth)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isSelected: Bool
        let fillsWidth: Bool
        @Environment(\.isFocused) private var isFocused

        private var foreground: Color {
            if isFocused { return .black }
            return isSelected ? Theme.Color.primaryText : Theme.Color.tertiaryText
        }

        private var fill: Color {
            if isFocused { return Theme.Color.primaryText }
            return isSelected ? Theme.Color.primaryText.opacity(0.18) : .clear
        }

        var body: some View {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).fill(fill)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.05 : 1.0))
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Stream-row card. Like `SettingsCardStyle` but with tighter vertical padding
/// so more streams fit on screen — a settings list has a few fat rows, a stream
/// list has many and benefits from density.
private struct StreamCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(isFocused ? Theme.Color.cardFocused : Theme.Color.cardRest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(isFocused ? Theme.Color.cardBorderFocused : .clear, lineWidth: 2)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.01 : 1.0))
                .animation(.easeInOut(duration: 0.16), value: isFocused)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
