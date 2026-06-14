

import Foundation
import CryptoKit

enum VaultStorageError: Error {
    case ciphertextMissing
    case metadataMissing
}

final class VaultFileCryptoService {

    private let crypto: CryptoService
    private let keyManager: KeyManager
    private let fileManager: FileManager

    private let encryptedDir: URL
    private let metadataDir: URL

    init(
        crypto: CryptoService = CryptoService(),
        keyManager: KeyManager = KeyManager(),
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) throws {
        self.crypto = crypto
        self.keyManager = keyManager
        self.fileManager = fileManager

        let base = try baseDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let vault = base.appendingPathComponent("Vault", isDirectory: true)
        self.encryptedDir = vault.appendingPathComponent("encrypted", isDirectory: true)
        self.metadataDir = vault.appendingPathComponent("metadata", isDirectory: true)

        try fileManager.createDirectory(at: encryptedDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metadataDir, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    private func ciphertextURL(for id: String) -> URL {
        encryptedDir.appendingPathComponent("\(id).vault")
    }

    private func metadataURL(for id: String) -> URL {
        metadataDir.appendingPathComponent("\(id).json")
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Import / Encrypt

    /// Encrypt raw bytes into the vault. This is the testable core.
    @discardableResult
    func encryptAndStore(
        data: Data,
        displayName: String,
        contentType: String
    ) throws -> VaultItemMetadata {

        // 1 + 2: fresh per-file key, persisted in Keychain by keyId.
        let (key, keyId) = try keyManager.generateKeyForNewItem()

        // 3: AES-GCM seal.
        let payload = try crypto.encrypt(data, using: key)

        let id = UUID().uuidString

        // 4: ciphertext blob only — no key, no nonce/tag in this file.
        try payload.ciphertext.write(to: ciphertextURL(for: id), options: .atomic)

        // 5: metadata (keyId + nonce + tag, never the key).
        let metadata = VaultItemMetadata(
            id: id,
            displayName: displayName,
            originalContentType: contentType,
            sizeBytes: data.count,
            createdAt: Date(),
            encryption: EncryptionMetadata(
                algorithm: payload.algorithm,
                nonce: payload.nonce,
                tag: payload.tag,
                keyId: keyId
            )
        )
        try persist(metadata)

        return metadata
    }

    /// Import a file the user picked. Reads it, encrypts it, and — if
    /// `removingSource` is true and we can write to it — deletes the plaintext
    /// original so no decrypted copy lingers.
    @discardableResult
    func importFile(at url: URL, removingSource: Bool = false) throws -> VaultItemMetadata {
        let data = try Data(contentsOf: url)
        let displayName = url.lastPathComponent
        let contentType = Self.contentType(for: url)

        let metadata = try encryptAndStore(
            data: data,
            displayName: displayName,
            contentType: contentType
        )

        if removingSource {
            try? fileManager.removeItem(at: url)
        }

        return metadata
    }

    // MARK: - Open / Decrypt

    /// Decrypt an item back into memory. Does NOT touch disk with plaintext.
    func decryptData(for metadata: VaultItemMetadata) throws -> Data {
        let cipherURL = ciphertextURL(for: metadata.id)
        guard fileManager.fileExists(atPath: cipherURL.path) else {
            throw VaultStorageError.ciphertextMissing
        }

        let ciphertext = try Data(contentsOf: cipherURL)
        let key = try keyManager.key(for: metadata.encryption.keyId)

        let payload = EncryptedPayload(
            algorithm: metadata.encryption.algorithm,
            nonce: metadata.encryption.nonce,
            ciphertext: ciphertext,
            tag: metadata.encryption.tag
        )

        return try crypto.decrypt(payload, using: key)
    }

    /// Decrypt to a temporary file (e.g. to hand to a preview/QuickLook).
    /// The CALLER owns the returned URL and must delete it when done — we keep
    /// plaintext on disk only as long as strictly necessary.
    func decryptToTemporaryFile(for metadata: VaultItemMetadata) throws -> URL {
        let data = try decryptData(for: metadata)
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((metadata.displayName as NSString).pathExtension)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - List / Delete

    func loadAllMetadata() throws -> [VaultItemMetadata] {
        let files = try fileManager.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return try files
            .map { try Self.jsonDecoder.decode(VaultItemMetadata.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Remove ciphertext, metadata, AND the Keychain key (crypto-shredding).
    func deleteItem(_ metadata: VaultItemMetadata) throws {
        try? fileManager.removeItem(at: ciphertextURL(for: metadata.id))
        try? fileManager.removeItem(at: metadataURL(for: metadata.id))
        try keyManager.deleteKey(for: metadata.encryption.keyId)
    }

    // MARK: - Helpers

    private func persist(_ metadata: VaultItemMetadata) throws {
        let data = try Self.jsonEncoder.encode(metadata)
        try data.write(to: metadataURL(for: metadata.id), options: .atomic)
    }

    /// Best-effort UTI/MIME guess from the file extension.
    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "txt":  return "text/plain"
        case "m4a":  return "audio/mp4"
        default:     return "application/octet-stream"
        }
    }
}
