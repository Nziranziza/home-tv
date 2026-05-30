import Foundation
import UIKit

enum ExternalPlayer: String, CaseIterable, Identifiable, Codable, Sendable {
    case infuse
    case vlc
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .infuse: "Infuse"
        case .vlc: "VLC"
        case .system: "System Default"
        }
    }

    var probeURL: URL? {
        switch self {
        case .infuse: URL(string: "infuse://")
        case .vlc: URL(string: "vlc-x-callback://")
        case .system: nil
        }
    }

    @MainActor
    var isInstalled: Bool {
        guard let probeURL else { return true }
        return UIApplication.shared.canOpenURL(probeURL)
    }
}
