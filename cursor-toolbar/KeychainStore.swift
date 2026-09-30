//
//  KeychainStore.swift
//  cursor-toolbar
//
//  Minimal generic-password wrapper for the few long-lived secrets the app holds
//  (LLM provider API keys). UserDefaults writes these to a plist that is readable
//  by anything running as the user and is captured verbatim by backups; the
//  keychain keeps them encrypted at rest and scoped to this app.
//

import Foundation
import Security

enum KeychainStore {
    /// Namespaced so entries are identifiable in Keychain Access and cannot
    /// collide with another app's items.
    private static let service = "com.crasi.janus"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Stores `value` for `account`, replacing any existing entry. An empty or
    /// whitespace-only value deletes the item instead of storing a blank secret.
    static func set(_ value: String, account: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delete(account: account)
            return
        }
        guard let data = value.data(using: .utf8) else { return }

        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available without an unlock prompt once the user has logged in, and
            // never synced to other devices — this is a machine-local credential.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// Reads a secret that older builds wrote to UserDefaults, moves it into the
    /// keychain, and clears the plaintext copy. Returns the value either way so
    /// callers can treat this as a plain read.
    static func migratingFromDefaults(account: String, defaultsKey: String) -> String {
        if let existing = get(account: account) { return existing }

        guard let legacy = UserDefaults.standard.string(forKey: defaultsKey),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }

        set(legacy, account: account)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return legacy
    }
}
