/// Debug-only player logging. `print`, because `devicectl --console` shows stdout but not `Logger`.
enum PlaybackDiagnostics {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Player] \(message())")
        #endif
    }
}
