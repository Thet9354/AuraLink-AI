//
//  ExemplarCryptor.swift
//  AuraLink AI
//
//  AES-GCM encryption for the exemplar library. Exemplars are biometric-adjacent (a recording of
//  how a specific person signs), so they are encrypted at rest with a device-only key. Pure over
//  its injected key, so the round-trip and the ciphertext-at-rest property are unit-testable.
//

import CryptoKit
import Foundation

nonisolated struct ExemplarCryptor: Sendable {

    let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    /// Encrypts plaintext into a self-describing AES-GCM box (nonce ‖ ciphertext ‖ tag).
    func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CryptoKitError.incorrectParameterSize
        }
        return combined
    }

    /// Decrypts a combined AES-GCM box back to plaintext.
    func decrypt(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}
