import Foundation
import os
import PressingCore
import Security

/// Production Keychain: the Last.fm session as one generic password item,
/// readable after the first unlock so Pressing works on a phone that has
/// sat locked beside the deck since it restarted. It stays on this device.
@MainActor
final class KeychainCredentials: Keychain {
    private let service = "Pressing.lastfm"
    private let account = "session"
    private let log = Logger(subsystem: "Pressing", category: "Keychain")

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func loadLastFmSession() -> LastFmSession? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(search as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound { log.error("The Last.fm session can't be read: \(status)") }
            return nil
        }
        return try? JSONDecoder().decode(LastFmSession.self, from: data)
    }

    func saveLastFmSession(_ session: LastFmSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { log.error("The Last.fm session can't be saved: \(status)") }
    }

    func deleteLastFmSession() {
        SecItemDelete(query as CFDictionary)
    }
}
