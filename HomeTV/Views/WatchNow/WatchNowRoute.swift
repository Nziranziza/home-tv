import SwiftUI

/// What the Watch Now navigation stack can push. An enum rather than `NavigationPath` so the path
/// stays typed, which is what lets the deep link replace the whole stack by assignment.
enum WatchNowRoute: Hashable {
    case detail(MetaPreview)
    case genre(Genre)
}

extension View {
    func watchNowDestinations(path: Binding<[WatchNowRoute]>) -> some View {
        navigationDestination(for: WatchNowRoute.self) { route in
            switch route {
            case .detail(let meta):
                MetaDetailDestination(meta: meta)
            case .genre(let genre):
                GenreBrowseView(genre: genre) { meta in
                    path.wrappedValue.append(.detail(meta))
                }
            }
        }
    }
}
