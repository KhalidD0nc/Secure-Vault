//
//  KeychainServiceTests.swift
//  Secure-VaultTests


import XCTest
@testable import Secure_Vault

final class KeychainServiceTests: XCTestCase {

    private var keychain: KeychainService!
    private let account = "test-account"

    override func setUp() {
        super.setUp()
        // Unique namespace per run so tests never collide with real data.
        keychain = KeychainService(service: "com.secure-vault.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? keychain.delete(account: account)
        keychain = nil
        super.tearDown()
    }

    func test_storeThenRead_returnsSameData() throws {
        let secret = Data("super-secret-bytes".utf8)

        try keychain.store(secret, account: account)
        let read = try keychain.read(account: account)

        XCTAssertEqual(read, secret)
    }

    func test_readMissing_throwsItemNotFound() {
        XCTAssertThrowsError(try keychain.read(account: "does-not-exist")) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func test_storeDuplicate_throwsDuplicateItem() throws {
        let secret = Data("x".utf8)
        try keychain.store(secret, account: account)

        XCTAssertThrowsError(try keychain.store(secret, account: account)) { error in
            XCTAssertEqual(error as? KeychainError, .duplicateItem)
        }
    }

    func test_delete_removesItem() throws {
        try keychain.store(Data("x".utf8), account: account)
        XCTAssertTrue(keychain.exists(account: account))

        try keychain.delete(account: account)

        XCTAssertFalse(keychain.exists(account: account))
        XCTAssertThrowsError(try keychain.read(account: account))
    }

    func test_delete_isIdempotent() throws {
        // Deleting a non-existent item must not throw (needed for crypto-shred).
        XCTAssertNoThrow(try keychain.delete(account: "never-stored"))
    }
}
