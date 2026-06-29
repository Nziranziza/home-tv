import SwiftUI

/// A landscape "Guest Appearances" card: a backdrop thumbnail above a caption (the person's role in
/// small caps, the show title, and the show overview). Mirrors `EpisodeCard`'s two-element structure —
/// the thumbnail is a focusable `.card` that lifts on focus while the caption stays put — so the
/// Guest Appearances row reads identically to the detail screen's episode strip.
struct CastTVCard: View {
    let item: FilmographyItem
    let action: () -> Void

    @FocusState private var focused: Bool

    private let width: CGFloat = 400
    private let imageHeight: CGFloat = 225

    private var thumbnailURL: URL? {
        (item.preview.background ?? item.preview.poster).flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: focused ? 28 : 8) {
            imageButton
            caption
        }
        .frame(width: width)
        .animation(.easeOut(duration: 0.25), value: focused)
    }

    private var imageButton: some View {
        Button(action: action) {
            RemoteImage(url: thumbnailURL,
                        targetSize: CGSize(width: width, height: imageHeight),
                        contentMode: .fill) {
                Color(white: 0.1)
            }
            .frame(width: width, height: imageHeight)
        }
        .buttonStyle(.card)
        .focused($focused)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let role = item.role, !role.isEmpty {
                Text(role.uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Text(item.preview.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let overview = item.preview.description, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: width, alignment: .topLeading)
        .background(focused ? Color.black.opacity(0.3) : Color.clear)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
