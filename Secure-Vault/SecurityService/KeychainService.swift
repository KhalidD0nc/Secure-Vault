//
//  KeychainService.swift
//  Secure-Vault
//
//  Day 2 — Key Management.
//
//  A thin, generic wrapper over the iOS Keychain (kSecClassGenericPassword).
//  It only knows how to store / read / delete raw `Data` blobs by an account
//  string. It does NOT know what a "file key" is — that meaning lives in
//  KeyManager. Keeping this layer dumb makes it reusable (we'll also store the
//  auth token here on Day 4) and easy to test.
//
//  Security attributes used on every item:
//    kSecAttrAccessibleWhenUnlockedThisDeviceOnly
//      - WhenUnlocked     : the secret is only readable while the device is unlocked.
//      - ThisDeviceOnly   : the secret never leaves this device via iCloud/iTunes
//                           backups, so key material can't migrate to another device.
//

import Foundation
import Security

enum KeychainError: Error, Equatable {
    /// No item exists for the requested account.
    case itemNotFound
    /// An item already exists (we treat add-on-existing as a logic error).
    case duplicateItem
    /// The stored bytes were not in the shape we expected.
    case unexpectedData
    /// Any other OSStatus the Security framework returned.
    case unhandled(OSStatus)
}

final class KeychainService {

    /// Namespace so our items don't collide with anything else on the device.
    private let service: String

    init(service: String = "com.secure-vault.filekeys") {
        self.service = service
    }

    /// Base query that identifies a single item: class + service + account.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    // MARK: - Create

    /// Store `data` under `account`. Throws `.duplicateItem` if it already exists.
    func store(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Read

    /// Read the bytes stored under `account`. Throws `.itemNotFound` if absent.
    func read(account: String) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Delete

    /// Remove the item under `account`. Succeeds silently if nothing was there
    /// (delete is idempotent — handy for crypto-shredding on item deletion).
    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Convenience

    /// Whether an item exists for `account`, without returning its bytes.
    func exists(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
