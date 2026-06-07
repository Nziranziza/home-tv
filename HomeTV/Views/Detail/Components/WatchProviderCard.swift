import SwiftUI

// MARK: - How to Watch provider card

/// One flattened "way to watch": a provider paired with a single availability (Stream / Rent / Buy).
struct WatchOption: Identifiable, Hashable {
    let id: String
    let provider: WatchProvider
    let availability: String
}

/// A single way to watch — provider logo + name, with the availability (Stream / Rent / Buy) as the
/// description. One card in the horizontal How to Watch row; uses the system `.card` button style.
struct WatchProviderCard: View {
    let provider: WatchProvider
    let availability: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RemoteImage(url: provider.logoURL, targetSize: CGSize(width: 56, height: 56), contentMode: .fit) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Color.cardRest)
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Color.primaryText)
                        .lineLimit(1)
                    Text(availability)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 340, alignment: .leading)
        }
        .buttonStyle(.card)
    }
}

