//
//  SecurityAndProbeTests.swift
//  AuraLink AITests
//
//  Phase 5 gates: exemplars are ciphertext at rest (and round-trip), and the device-capability
//  table classifies known identifiers correctly.
//

import CryptoKit
import Foundation
import Testing
@testable import AuraLink_AI

struct ExemplarCryptorTests {

    @Test func encryptDecryptRoundTrips() throws {
        let cryptor = ExemplarCryptor(key: SymmetricKey(size: .bits256))
        let plaintext = Data("water exemplar payload".utf8)
        let sealed = try cryptor.encrypt(plaintext)
        #expect(sealed != plaintext)                         // it actually transformed the bytes
        #expect(try cryptor.decrypt(sealed) == plaintext)    // and recovers exactly
    }

    @Test func wrongKeyFailsToDecrypt() throws {
        let a = ExemplarCryptor(key: SymmetricKey(size: .bits256))
        let b = ExemplarCryptor(key: SymmetricKey(size: .bits256))
        let sealed = try a.encrypt(Data("secret".utf8))
        #expect((try? b.decrypt(sealed)) == nil)
    }
}

struct EncryptedExemplarStoreTests {

    private func fixedCryptor() -> ExemplarCryptor {
        ExemplarCryptor(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
    }

    @Test func exemplarIsCiphertextAtRest() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLinkSec-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ExemplarFileStore(directory: dir, cryptor: fixedCryptor())
        try await store.save(SignExemplar(lexID: "water", frames: FeatureFactory.exemplarFrames(seed: 1, count: 8)))

        // Inspect the raw bytes on disk: the lex id / JSON keys must NOT appear in plaintext.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let sealed = try #require(files.first { $0.pathExtension == "sealed" })
        let bytes = try Data(contentsOf: sealed)
        #expect(!bytes.contains(Data("water".utf8)))
        #expect(!bytes.contains(Data("lexID".utf8)))

        // But the store still decrypts it back.
        let loaded = try await store.loadAll()
        #expect(loaded.first?.lexID == "water")
    }

    @Test func plaintextStoreCannotReadSealedFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLinkSec-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await ExemplarFileStore(directory: dir, cryptor: fixedCryptor())
            .save(SignExemplar(lexID: "help", frames: FeatureFactory.exemplarFrames(seed: 2, count: 8)))

        // A store without the cryptor scans .json; the encrypted .sealed files are invisible to it.
        let plain = ExemplarFileStore(directory: dir)
        #expect(try await plain.loadAll().isEmpty)
    }
}

struct CapabilityProbeTests {

    @Test func classifiesKnownIdentifiers() {
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone13,2") == .a14floor)   // iPhone 12 (A14)
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone14,2") == .a15)        // iPhone 13 Pro (A15)
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone15,4") == .a15)        // iPhone 15 (A16)
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone16,1") == .a17plus)    // iPhone 15 Pro (A17 Pro)
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone17,1") == .a17plus)    // iPhone 16 Pro (A18 Pro)
    }

    @Test func unknownIdentifierIsNotInTable() {
        #expect(CapabilityProbe.rung(forIdentifier: "iPhone99,9") == nil)
    }

    @Test func detectRungNeverTraps() {
        // On the simulator this exercises the heuristic/fallback path without crashing.
        let rung = CapabilityProbe.detectRung()
        #expect(DeviceRung.allCases.contains(rung))
    }
}
