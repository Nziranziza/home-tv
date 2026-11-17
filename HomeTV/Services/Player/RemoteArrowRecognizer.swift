import UIKit

/// Watches the remote's Left/Right presses and tells a click from a press-and-hold. SwiftUI's move command
/// fires once on press and can't see a hold. It never recognizes, so focus and other gestures are untouched.
@MainActor
final class RemoteArrowRecognizer: UIGestureRecognizer {
    /// How long a press lasts before it's a hold; the system player starts scanning after about this long.
    static let holdDelay: Duration = .milliseconds(300)

    /// The press went down. Return true to spend it, so it's neither a click nor a hold.
    var onPress: ((PlayerScan.Direction) -> Bool)?
    var onClick: ((PlayerScan.Direction) -> Void)?
    var onHold: ((PlayerScan.Direction) -> Void)?

    private var down: (side: PlayerScan.Direction, press: UIPress)?
    private var holdTask: Task<Void, Never>?

    init() {
        super.init(target: nil, action: nil)
        allowedPressTypes = [UIPress.PressType.leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
        cancelsTouchesInView = false
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard down == nil, let press = presses.first, let side = Self.side(of: press) else { return }
        if onPress?(side) == true { return }
        down = (side, press)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled, let self, let down else { return }
            self.down = nil
            onHold?(down.side)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        if let down, presses.contains(down.press) {
            onClick?(down.side)
        }
        finish(presses)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        finish(presses)
    }

    override func reset() {
        super.reset()
        holdTask?.cancel()
        holdTask = nil
        down = nil
    }

    private func finish(_ presses: Set<UIPress>) {
        holdTask?.cancel()
        holdTask = nil
        down = nil
        // Failing resets the recognizer for the next press.
        state = .failed
    }

    private static func side(of press: UIPress) -> PlayerScan.Direction? {
        switch press.type {
        case .leftArrow: .backward
        case .rightArrow: .forward
        default: nil
        }
    }
}
