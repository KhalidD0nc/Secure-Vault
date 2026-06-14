//
//  CryptoServiceTests.swift
//  Secure-VaultTests
//
//  Day 1 — Local Crypto Core tests.
//  Proves AES-GCM gives confidentiality AND integrity:
//  any tamper to ciphertext/tag, or a wrong key, makes decrypt fail.
//

import XCTest
import CryptoKit
@testable import Secure_Vault

final class CryptoServiceTests: XCTestCase {

    private let crypto = CryptoService()

    private func sampleData() -> Data {
        Data("hello secure vault".utf8)
    }

    // decrypt(encrypt(data)) == data
    func test_roundTrip_returnsOriginalData() throws {
        let key = crypto.generateKey()
        let data = sampleData()

        let payload = try crypto.encrypt(data, using: key)
        let decrypted = try crypto.decrypt(payload, using: key)

        XCTAssertEqual(decrypted, data)
    }

    // ciphertext should NOT equal plaintext
    func test_ciphertext_differsFromPlaintext() throws {
        let key = crypto.generateKey()
        let data = sampleData()

        let payload = try crypto.encrypt(data, using: key)

        XCTAssertNotEqual(payload.ciphertext, data)
        XCTAssertEqual(payload.algorithm, "AES-256-GCM")
    }

    // tampered ciphertext -> decrypt fails (integrity)
    func test_tamperedCiphertext_failsToDecrypt() throws {
        let key = crypto.generateKey()
        let payload = try crypto.encrypt(sampleData(), using: key)

        var badCiphertext = Data(payload.ciphertext)   // re-bases indices to 0
        badCiphertext[0] ^= 0xFF

        let tampered = EncryptedPayload(
            algorithm: payload.algorithm,
            nonce: payload.nonce,
            ciphertext: badCiphertext,
            tag: payload.tag
        )

        XCTAssertThrowsError(try crypto.decrypt(tampered, using: key))
    }

    // tampered tag -> decrypt fails
    func test_tamperedTag_failsToDecrypt() throws {
        let key = crypto.generateKey()
        let payload = try crypto.encrypt(sampleData(), using: key)

        var badTag = Data(payload.tag)
        badTag[0] ^= 0xFF

        let tampered = EncryptedPayload(
            algorithm: payload.algorithm,
            nonce: payload.nonce,
            ciphertext: payload.ciphertext,
            tag: badTag
        )

        XCTAssertThrowsError(try crypto.decrypt(tampered, using: key))
    }

    // wrong key -> decrypt fails
    func test_wrongKey_failsToDecrypt() throws {
        let key = crypto.generateKey()
        let wrongKey = crypto.generateKey()

        let payload = try crypto.encrypt(sampleData(), using: key)

        XCTAssertThrowsError(try crypto.decrypt(payload, using: wrongKey))
    }

    // wrong nonce -> decrypt fails
    func test_wrongNonce_failsToDecrypt() throws {
        let key = crypto.generateKey()
        let payload = try crypto.encrypt(sampleData(), using: key)

        let wrongNonce = AES.GCM.Nonce()
        let tampered = EncryptedPayload(
            algorithm: payload.algorithm,
            nonce: wrongNonce.withUnsafeBytes { Data($0) },
            ciphertext: payload.ciphertext,
            tag: payload.tag
        )

        XCTAssertThrowsError(try crypto.decrypt(tampered, using: key))
    }
}
