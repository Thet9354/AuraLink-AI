//
//  ExemplarKeyStore.swift
//  AuraLink AI
//
//  Provides the symmetric key used to encrypt the exemplar library. The key is generated once and
//  persisted in the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — so it never
//  syncs, never leaves the device, and (on devices with a Secure Enclave) is protected by the
//  hardware-backed keychain. A future revision can wrap this key with a `SecureEnclave.P256` key
//  for enclave-bound key agreement; the seam is `EncryptionKeyProviding`.
//

import CryptoKit
import Foundation
import Security

nonisolated protocol EncryptionKeyProviding: Sendable {
    func key() throws -> SymmetricKey
}

nonisolated struct KeychainKeyProvider: EncryptionKeyProviding {

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    private let account: String

    init(account: String = "com.thetpine.auralink.exemplar-key") {
        self.account = account
    }

    /// Loads the existing key, or generates and stores a new 256-bit key on first use.
    func key() throws -> SymmetricKey {
        if let existing = try load() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try store(newKey)
        return newKey
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "AuraLinkExemplarEncryption"
        ]
    }

    private func load() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func store(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
