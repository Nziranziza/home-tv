import SwiftUI

// MARK: - Hero chip badges

/// PLACEHOLDER capability chips — real values (4K/Dolby/CC/SDH/AD) will come from addons. Chip styles
/// per the spec: 4K is a filled light chip with dark text; the rest are outlined (white @ 0.55).
struct QualityBadges: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("4K")
                .font(.system(size: 19, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                )
                .foregroundStyle(.black.opacity(0.85))
            ForEach(["CC", "SDH", "AD"], id: \.self) { badge in
                OutlinedBadge(text: badge)
            }
        }
    }
}

/// The shared outlined metadata chip (white stroke, light text) used by the hero capability chips and
/// the Accessibility SDH / AD badges, so both read identically.
struct OutlinedBadge: View {
    let text: String
    var tint: Color = .white.opacity(0.9)

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(tint.opacity(0.65), lineWidth: 1)
            )
            .foregroundStyle(tint)
    }
}

