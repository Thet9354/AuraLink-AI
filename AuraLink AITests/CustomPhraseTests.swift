//
//  CustomPhraseTests.swift
//  AuraLink AITests
//
//  Custom phrases present as lexicon entries and round-trip through the encrypted store.
//

import CryptoKit
import Foundation
import Testing
@testable import AuraLink_AI

struct CustomPhraseTests {

    @Test func presentsAsCustomLexEntry() {
        let phrase = CustomPhrase(title: "Help", text: "I need help please")
        let entry = phrase.asLexEntry
        #expect(entry.id == phrase.id)
        #expect(entry.english == "I need help please")
        #expect(entry.category == .custom)
        #expect(entry.isCustom)
    }

    @Test func mergesIntoLexiconAndResolves() {
        let catalog = SignLexicon(entries: [
            LexEntry(id: "water", gloss: "WATER", english: "water", category: .need)
        ])
        let phrase = CustomPhrase(title: "Bathroom", text: "I need to use the bathroom")
        let merged = SignLexicon(entries: catalog.entries + [phrase.asLexEntry])
        #expect(merged[phrase.id]?.english == "I need to use the bathroom")
        #expect(merged["water"] != nil)
    }

    private func tempStore() -> (CustomPhraseFileStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLinkPhrases-\(UUID().uuidString)", isDirectory: true)
        let cryptor = ExemplarCryptor(key: SymmetricKey(data: Data(repeating: 9, count: 32)))
        return (CustomPhraseFileStore(directory: dir, cryptor: cryptor), dir)
    }

    @Test func savesLoadsAndRemoves() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let phrase = CustomPhrase(title: "Hi", text: "Hello there")
        try await store.save(phrase)

        let loaded = try await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "Hello there")

        try await store.remove(id: phrase.id)
        #expect(try await store.loadAll().isEmpty)
    }

    @Test func encryptsPhraseTextAtRest() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.save(CustomPhrase(title: "Secret", text: "meet me at noon"))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let sealed = try #require(files.first { $0.pathExtension == "sealed" })
        let bytes = try Data(contentsOf: sealed)
        #expect(!bytes.contains(Data("meet me at noon".utf8)))   // ciphertext at rest
    }
}
