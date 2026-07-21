import SwiftUI

/// The static footer row: Information / Languages / Accessibility side by side. Information is a frosted
/// card; Languages and Accessibility are plain text (with the inline "MORE" cue where truncated).
struct DetailInformationSection: View {
    let model: MetaDetailModel
    /// Episode-detail overrides: when set, the Information card shows the episode's own release year and
    /// run time instead of the show-level values (the rest of the block stays show-level). nil on the
    /// title detail, which shows the show's values.
    var releasedOverride: String? = nil
    var runtimeOverride: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            InformationColumn(model: model, releasedOverride: releasedOverride, runtimeOverride: runtimeOverride)
            LanguagesColumn(model: model)
            AccessibilityColumn()
        }
        // Leading at the block guide; trailing tuned so the three equal columns land on the reference
        // guides (text at ≈ 80 / 686 / 1292pt).
        .padding(.leading, DetailLayout.infoBlockInset)
        .padding(.trailing, 62)
        // Generous bottom region so the focus engine's auto-scroll never scrolls past the footer; below
        // it the page's own warm blurred gradient shows through (no dark shelf — one continuous gradient).
        .padding(.bottom, 600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { FooterPanel() }
        .padding(.top, DetailLayout.footerTopGap)   // About card → header gap, matched to the reference (≈90pt)
        .focusSection()
    }
}

/// A dark translucent scrim behind the footer so it reads darker than the rest of the page, fading
/// out toward the bottom back to the bare backdrop. Bleeds up into the gap above the headers.
private struct FooterPanel: View {
    var body: some View {
        // A gradient fill directly (black→clear), NOT a solid rect masked by a gradient — the mask forced
        // an offscreen alpha pass over this large area every frame. Same pixels: the old white→clear mask
        // multiplied the 0.42 black, which is exactly a black-0.42→clear gradient.
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.42), location: 0.0),
                .init(color: .black.opacity(0.42), location: 0.42),
                .init(color: .clear, location: 0.82)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .padding(.top, -DetailLayout.footerPanelTopBleed)
        .allowsHitTesting(false)
    }
}

private struct InformationColumn: View {
    let model: MetaDetailModel
    var releasedOverride: String? = nil
    var runtimeOverride: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Information")
            InfoColumnCard {
                if let year = releasedOverride ?? model.meta?.releaseInfo, !year.isEmpty {
                    InfoPair(label: "Released", value: year)
                }
                if let runtime = runtimeOverride ?? model.vm.displayRuntime {
                    InfoPair(label: "Run Time", value: runtime)
                }
                InfoPair(label: "Rated", value: model.vm.displayCertification)
                if let status = model.enrichment?.status, !status.isEmpty {
                    InfoPair(label: "Status", value: status)
                }
                if !model.vm.displayGenres.isEmpty {
                    InfoPair(label: "Genre", value: model.vm.displayGenres.joined(separator: ", "))
                }
                // PLACEHOLDER — TMDB enrichment has no content-advisory field yet; real advisories are a
                // separate data feature. Matches the Apple TV+ layout in the meantime.
                InfoPair(label: "Content Advisories", value: "Violence, Language")
                InfoPair(label: "Regions of Origin", value: model.enrichment?.country ?? "United States")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LanguagesColumn: View {
    let model: MetaDetailModel

    // PLACEHOLDER strings — language/subtitle tracks come from the stream/addon, not basic meta.
    private let audioLanguages = "English (Dolby Atmos, Dolby 5.1, AAC, AD), French (Canada) (Dolby 5.1, AAC, AD), French (France) (Dolby 5.1, AAC, AD), German (Dolby 5.1, AAC, AD), Italian (Dolby 5.1, AAC, AD), Japanese (Dolby 5.1, AAC, AD), Portuguese (Brazil) (Dolby 5.1, AAC, AD), Spanish"
    private let subtitleLanguages = "English (CC, SDH), Arabic (SDH), Bulgarian (SDH), Cantonese, Traditional (SDH), Chinese, Simplified (SDH), Chinese, Traditional (SDH), Czech (SDH), Danish (SDH), Dutch (SDH), Estonian (SDH), Finnish (SDH), French (Canada) (SDH), French (France) (SDH), German (SDH), Greek (SDH), Hungarian (SDH), Italian (SDH), Japanese (SDH)"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Languages")
            InfoColumnCard(spacing: 22) {
                InfoPair(label: "Original Audio", value: model.enrichment?.language ?? "English")
                InfoPair(label: "Audio", value: audioLanguages, lineLimit: 4)
                InfoPair(label: "Subtitles", value: subtitleLanguages, lineLimit: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessibilityColumn: View {
    // PLACEHOLDER strings — accessibility flags come from the stream/addon, not basic meta.
    private let sdhDescription = "Subtitles for the deaf and hard of hearing (SDH) refer to subtitles in the original language with the addition of relevant non-dialogue information."
    private let adDescription = "Audio descriptions (AD) refer to a narration track describing what is happening on screen, to provide context for those who are blind or have low vision."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoColumnHeader(title: "Accessibility")
            InfoColumnCard(spacing: 26) {
                AccessibilityItem(badge: "SDH", description: sdhDescription)
                AccessibilityItem(badge: "AD", description: adDescription)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
