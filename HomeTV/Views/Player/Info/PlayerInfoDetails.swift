import SwiftUI

/// The Info panel's text: the bold title, a two-line synopsis, and the genre and runtime with badges.
struct PlayerInfoDetails: View {
    let title: String
    let synopsis: String?
    let line: String?
    let badges: [PlayerBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.body)
                .bold()
                .foregroundStyle(.white)
                .lineLimit(1)
            if let synopsis {
                Text(synopsis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            HStack(spacing: 16) {
                if let line {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                ForEach(badges, id: \.self) { badge in
                    PlayerBadgeView(badge: badge)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxHeight: PlayerInfoPoster.size.height, alignment: .topLeading)
    }
}
