import SwiftUI

/// Muted rail header ("About") + a frosted card with the title, genre, and synopsis.
struct DetailAboutSection: View {
    let model: MetaDetailModel
    let scroll: DetailScrollState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailSectionHeader(title: "About", leadingInset: DetailLayout.infoBlockInset, scroll: scroll)
            AboutCard(model: model)
                .padding(.leading, DetailLayout.infoBlockInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// The card with the title, genre, and synopsis. A focusable, informational card (empty action) that
/// matches the Information columns: plain at rest, a Liquid Glass panel + native lift on focus via the
/// shared `.glassCard` style.
private struct AboutCard: View {
    let model: MetaDetailModel

    var body: some View {
        Button { } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.meta?.name ?? model.fallbackTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let genre = model.vm.displayGenres.first, !genre.isEmpty {
                    Text(genre)
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.top, 4)
                }
                if let description = model.vm.displayDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 24))
                        .foregroundStyle(Color(white: 0.93))   // ≈ #EDEDED
                        .lineSpacing(4)
                        .padding(.top, 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: DetailLayout.infoCardWidth - DetailLayout.infoCardPadding * 2, alignment: .leading)
            .padding(DetailLayout.infoCardPadding)
        }
        .buttonStyle(.glassCard(cornerRadius: 22))
    }
}
