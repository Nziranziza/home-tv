import Foundation
import Security

/// Minimal generic-password Keychain wrapper. The app's first use of the Keychain — Stremio addons
/// and watch history live in UserDefaults, but OAuth tokens are credentials, so they belong here.
///
/// One service ("com.hometv.trakt"); each value keyed by an account string. Values are stored as
/// UTF-8 data. All methods are best-effort: failures return `false`/`nil` rather than throwing, which
/// matches how the rest of the app treats persistence (see AddonRegistry/WatchHistory).
enum Keychain {
    private static let service = "com.hometv.trakt"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Replace any existing item: delete then add keeps this simple and atomic enough for our use.
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
