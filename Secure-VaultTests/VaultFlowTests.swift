//
//  VaultFlowTests.swift
//  Secure-VaultTests
//


import XCTest
import CryptoKit
@testable import Secure_Vault

final class VaultFlowTests: XCTestCase {

    private var baseDir: URL!
    private var keychain: KeychainService!
    private var vault: VaultFileCryptoService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-tests-\(UUID().uuidString)", isDirectory: true)

        keychain = KeychainService(service: "com.secure-vault.tests.\(UUID().uuidString)")
        let keyManager = KeyManager(keychain: keychain)

        vault = try VaultFileCryptoService(
            crypto: CryptoService(),
            keyManager: keyManager,
            baseDirectory: baseDir
        )
    }

    override func tearDownWithError() throws {
        // Best-effort cleanup of files; Keychain items use a unique service so
        // they can't leak into other runs.
        try? FileManager.default.removeItem(at: baseDir)
        vault = nil
        keychain = nil
        baseDir = nil
        try super.tearDownWithError()
    }

    private var encryptedDir: URL {
        baseDir.appendingPathComponent("Vault/encrypted", isDirectory: true)
    }

    private func ciphertextURL(_ id: String) -> URL {
        encryptedDir.appendingPathComponent("\(id).vault")
    }

    // import -> encrypted blob exists, and the stored bytes are NOT the plaintext
    func test_encryptAndStore_writesCiphertextNotPlaintext() throws {
        let plaintext = Data("top secret note".utf8)

        let item = try vault.encryptAndStore(
            data: plaintext,
            displayName: "note.txt",
            contentType: "text/plain"
        )

        let stored = try Data(contentsOf: ciphertextURL(item.id))
        XCTAssertFalse(stored.isEmpty)
        XCTAssertNotEqual(stored, plaintext)
        XCTAssertEqual(item.encryption.algorithm, "AES-256-GCM")
        XCTAssertEqual(item.sizeBytes, plaintext.count)
    }

    // decrypt round-trips back to the original bytes
    func test_decrypt_returnsOriginalData() throws {
        let plaintext = Data("round trip me".utf8)
        let item = try vault.encryptAndStore(data: plaintext, displayName: "n.txt", contentType: "text/plain")

        let decrypted = try vault.decryptData(for: item)

        XCTAssertEqual(decrypted, plaintext)
    }

    // importFile(removingSource:) deletes the plaintext original
    func test_importFile_removesPlaintextSource() throws {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).txt")
        try Data("delete me after import".utf8).write(to: src)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))

        let item = try vault.importFile(at: src, removingSource: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path),
                       "plaintext source should be removed after encryption")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ciphertextURL(item.id).path))
    }

    // integrity: flipping a byte in the stored ciphertext makes decrypt fail
    func test_tamperedCiphertextOnDisk_failsToDecrypt() throws {
        let item = try vault.encryptAndStore(data: Data("integrity".utf8), displayName: "n.txt", contentType: "text/plain")

        var bytes = try Data(contentsOf: ciphertextURL(item.id))
        bytes[0] ^= 0xFF
        try bytes.write(to: ciphertextURL(item.id))

        XCTAssertThrowsError(try vault.decryptData(for: item))
    }

    // deleteItem performs crypto-shredding: key gone, decrypt impossible
    func test_deleteItem_shredsKeyAndFiles() throws {
        let item = try vault.encryptAndStore(data: Data("shred".utf8), displayName: "n.txt", contentType: "text/plain")
        let keyId = item.encryption.keyId

        try vault.deleteItem(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ciphertextURL(item.id).path))
        XCTAssertFalse(keychain.exists(account: keyId), "key must be removed from Keychain")
        XCTAssertThrowsError(try vault.decryptData(for: item))
    }

    // metadata persists and reloads, and never contains key material
    func test_loadAllMetadata_roundTripsAndExcludesKey() throws {
        let item = try vault.encryptAndStore(data: Data("a".utf8), displayName: "a.txt", contentType: "text/plain")

        let all = try vault.loadAllMetadata()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, item.id)

        // The on-disk metadata JSON must not contain raw key bytes — only keyId.
        let metaURL = baseDir.appendingPathComponent("Vault/metadata/\(item.id).json")
        let json = try String(contentsOf: metaURL, encoding: .utf8)
        XCTAssertTrue(json.contains(item.encryption.keyId))
        XCTAssertFalse(json.lowercased().contains("\"key\""))
    }
}
