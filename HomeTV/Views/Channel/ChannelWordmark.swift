import SwiftUI

/// A channel's wordmark in white, or its name set in text until the logo loads or when it fails.
struct ChannelWordmark: View {
    let channel: StreamingChannel
    let logoURL: URL?
    let maxSize: CGSize
    var font: Font = .title3.bold()
    var alignment: Alignment = .center

    var body: some View {
        RemoteImage(url: logoURL, targetSize: maxSize, contentMode: .fit, renderingMode: .template) {
            Text(channel.name)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height, alignment: alignment)
        .accessibilityLabel(channel.name)
    }
}
