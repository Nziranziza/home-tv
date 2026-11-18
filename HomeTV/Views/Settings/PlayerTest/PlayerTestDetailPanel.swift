import SwiftUI

/// Explains the focused file: where it's from, what should happen, what to check, and its specs.
struct PlayerTestDetailPanel: View {
    let selection: PlayerTestSelection
    let scope: PlayerTestScope
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let entry = selection.entry {
                PlayerTestEntryDetail(entry: entry)
            } else {
                VStack(alignment: .leading) {
                    Text(scope.title).font(.headline)
                    Text(scope.summary).font(.callout).foregroundStyle(theme.secondaryText)
                    Text("Move to a file to see what it tests. Select plays it in HomeTV; the Infuse button beside it opens the same file in Infuse.")
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                }
                .foregroundStyle(theme.primaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.rowHorizontal)
        .background(theme.cardRest, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(.vertical, Theme.Spacing.stack)
    }
}

private struct PlayerTestEntryDetail: View {
    let entry: PlayerTestEntry
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.stack) {
            VStack(alignment: .leading) {
                Text(entry.breadcrumb).font(.caption).foregroundStyle(theme.secondaryText)
                Text(entry.item.title).font(.headline).lineLimit(2)
            }
            PlayerTestExpectationBadge(expect: entry.expect)

            VStack(alignment: .leading) {
                Text("What to check").font(.callout).bold()
                ForEach(PlayerTestGuide.checks(for: entry), id: \.self) { check in
                    Label(check, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline) {
                ForEach(specs, id: \.label) { spec in
                    GridRow {
                        Text(spec.label).foregroundStyle(theme.tertiaryText)
                        Text(spec.value).lineLimit(2).truncationMode(.middle)
                    }
                }
            }
            .font(.caption)
        }
        .foregroundStyle(theme.primaryText)
    }

    private var specs: [(label: String, value: String)] {
        let item = entry.item
        var specs: [(String, String)] = [("Container", item.container.uppercased())]
        if let video = item.video { specs.append(("Video", PlayerTestVocabulary.codecName(video))) }
        if let audio = item.audio { specs.append(("Audio", PlayerTestVocabulary.codecName(audio))) }
        if let resolution = item.resolution { specs.append(("Resolution", resolution)) }
        if let hdr = item.hdr { specs.append(("HDR", PlayerTestVocabulary.hdrName(hdr))) }
        if let bitrate = item.bitrateText { specs.append(("Bitrate", bitrate)) }
        if let size = item.sizeText { specs.append(("Size", size)) }
        specs.append(("File", item.filename))
        if let host = item.url.host() { specs.append(("Source", host)) }
        if let reason = item.infuseBlockReason { specs.append(("Infuse", reason)) }
        return specs
    }
}
