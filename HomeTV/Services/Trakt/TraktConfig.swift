import Foundation

/// Trakt API credentials. These identify *this app* to Trakt — they are not user credentials.
///
/// The values live in `Secrets.xcconfig` (gitignored), are injected into Info.plist at build time via
/// `$(TRAKT_CLIENT_ID)` / `$(TRAKT_CLIENT_SECRET)` substitution (see project.yml), and are read here
/// at runtime with `Bundle.main`. Nothing secret is committed to source.
///
/// To set up (one-time):
///   1. `cp Secrets.example.xcconfig Secrets.xcconfig`
///   2. Create a Trakt app at https://trakt.tv/oauth/applications with Redirect URI
///      `urn:ietf:wg:oauth:2.0:oob`, then paste its Client ID / Client Secret into Secrets.xcconfig.
///   3. `xcodegen generate` && build.
///
/// Leaving the values blank is fine — the app builds and the Trakt row hides itself (`isConfigured`).
enum TraktConfig {
    static let clientID = infoValue("TRAKT_CLIENT_ID")
    static let clientSecret = infoValue("TRAKT_CLIENT_SECRET")

    /// Device-flow / refresh use the out-of-band redirect — no real callback URL is involved.
    static let redirectURI = "urn:ietf:wg:oauth:2.0:oob"

    static let apiBaseURL = URL(string: "https://api.trakt.tv")!

    /// True once both credentials are present. The whole Trakt UI keys off this.
    static var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    /// Read an Info.plist string injected from the xcconfig, trimming any stray whitespace/newlines
    /// from copy-paste. Returns "" when unset (key absent or left blank in the xcconfig).
    private static func infoValue(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
