//
//  CryptoService.swift
//  Secure-Vault
//
//  Created by Khalid R on 10/06/2026.
//

import Foundation
import CryptoKit

struct EncryptedPayload: Codable {
    let algorithm: String
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

final class CryptoService {
    func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> EncryptedPayload {
        let sealedBox = try AES.GCM.seal(data, using: key)

        return EncryptedPayload(
            algorithm: "AES-256-GCM",
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    func decrypt(_ payload: EncryptedPayload, using key: SymmetricKey) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: payload.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: payload.ciphertext,
            tag: payload.tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }
}
