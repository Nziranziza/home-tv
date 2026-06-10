import SwiftUI

// MARK: - How to Watch provider card

/// One flattened "way to watch": a provider paired with a single availability (Stream / Rent / Buy).
struct WatchOption: Identifiable, Hashable {
    let id: String
    let provider: WatchProvider
    let availability: String
}

/// A single way to watch — provider logo + name, with the availability (Stream / Rent / Buy) as the
/// description. One cell in the How to Watch grid; uses the system `.card` button style. The square
/// provider logo sits in a square tile and the card fills its grid column.
struct WatchProviderCard: View {
    let provider: WatchProvider
    let availability: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                logoTile
                VStack(alignment: .leading, spacing: 6) {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Color.primaryText)
                        .lineLimit(2)
                    Text(availability)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.card)
    }

    /// Square logo tile: the provider's square watch-provider icon, fit on a dark rounded panel.
    private var logoTile: some View {
        RemoteImage(url: provider.logoURL, targetSize: CGSize(width: 108, height: 108), contentMode: .fit) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Color.cardRest)
        }
        .frame(width: 108, height: 108)
        .background(Color.black.opacity(0.35), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
    }
}

