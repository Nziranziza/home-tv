import SwiftUI

/// What the Watch Now navigation stack can push. An enum rather than `NavigationPath` so the path
/// stays typed, which is what lets the deep link replace the whole stack by assignment.
enum WatchNowRoute: Hashable {
    case detail(MetaPreview)
    case genre(Genre)
    case channel(StreamingChannel)
}

extension View {
    /// `isStackVisible` is false while the tab is off-screen or a cover is up, so a pushed channel's
    /// hero can stand its trailer down like Watch Now's does.
    func watchNowDestinations(
        path: Binding<[WatchNowRoute]>,
        isStackVisible: Bool,
        onPlay: @escaping (MetaPreview) -> Void
    ) -> some View {
        navigationDestination(for: WatchNowRoute.self) { route in
            switch route {
            case .detail(let meta):
                MetaDetailDestination(meta: meta)
            case .genre(let genre):
                GenreBrowseView(genre: genre) { meta in
                    path.wrappedValue.append(.detail(meta))
                }
            case .channel(let channel):
                ChannelView(
                    channel: channel,
                    isActive: isStackVisible && path.wrappedValue.last == route,
                    onPlay: onPlay
                ) { meta in
                    path.wrappedValue.append(.detail(meta))
                }
                .id(channel.id)
            }
        }
    }
}
