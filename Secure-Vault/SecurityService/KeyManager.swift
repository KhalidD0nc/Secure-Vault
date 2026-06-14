//
//  KeyManager.swift
//  Secure-Vault
//


import Foundation
import CryptoKit

final class KeyManager {

    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    /// Generate a fresh AES-256 key for a new item, persist it in the Keychain,
    /// and return both the key (for immediate use) and its keyId (for metadata).
    func generateKeyForNewItem() throws -> (key: SymmetricKey, keyId: String) {
        let keyId = UUID().uuidString
        let key = SymmetricKey(size: .bits256)

        // SymmetricKey -> raw Data (32 bytes) for storage.
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychain.store(keyData, account: keyId)

        return (key, keyId)
    }

    /// Fetch the key for an existing item. Throws `KeychainError.itemNotFound`
    /// if the key is missing (e.g. it was shredded or never existed).
    func key(for keyId: String) throws -> SymmetricKey {
        let keyData = try keychain.read(account: keyId)
        return SymmetricKey(data: keyData)
    }

    /// Permanently remove an item's key. After this the matching ciphertext can
    /// never be decrypted again. Idempotent.
    func deleteKey(for keyId: String) throws {
        try keychain.delete(account: keyId)
    }
}
