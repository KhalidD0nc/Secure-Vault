
import Foundation

struct EncryptionMetadata: Codable, Equatable {
    let algorithm: String   // "AES-256-GCM"
    let nonce: Data          // base64 in JSON
    let tag: Data            // base64 in JSON
    let keyId: String        // Keychain account; NOT the key itself
}

struct VaultItemMetadata: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let originalContentType: String
    let sizeBytes: Int
    let createdAt: Date
    let encryption: EncryptionMetadata
}
