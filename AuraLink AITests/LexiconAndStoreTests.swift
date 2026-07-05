//
//  LexiconAndStoreTests.swift
//  AuraLink AITests
//
//  Phase 3 gate: the bundled catalog decodes and is well-formed, and the exemplar store round-trips
//  including layout-version filtering (a stale exemplar must be skipped, never misinterpreted).
//

import Foundation
import Testing
@testable import AuraLink_AI

struct LexiconTests {

    @Test func bundledCatalogDecodesAndIsWellFormed() throws {
        let lexicon = LexiconLoader.loadBundled()
        #expect(lexicon.count >= 200)                        // ~200-sign Everyday Needs v1

        let ids = lexicon.entries.map(\.id)
        #expect(Set(ids).count == ids.count)                 // ids unique
        #expect(lexicon.entries.allSatisfy { !$0.english.isEmpty && !$0.gloss.isEmpty })
        #expect(lexicon["me"] != nil)                        // pronoun used by grammar mapping
        #expect(lexicon["thank_you"] != nil)

        // Every category used by the enrollment UI has at least one entry.
        #expect(!lexicon.entries(in: .emergency).isEmpty)
        #expect(!lexicon.entries(in: .number).isEmpty)
    }
}

struct ExemplarFileStoreTests {

    private func tempStore() -> (ExemplarFileStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLinkTests-\(UUID().uuidString)", isDirectory: true)
        return (ExemplarFileStore(directory: dir), dir)
    }

    @Test func savesAndLoadsRoundTrip() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exemplar = SignExemplar(lexID: "water", frames: FeatureFactory.exemplarFrames(seed: 1, count: 15))
        try await store.save(exemplar)

        let loaded = try await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.lexID == "water")
        #expect(loaded.first?.frames.count == 15)
    }

    @Test func countsAggregateByLexID() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.save(SignExemplar(lexID: "water", frames: FeatureFactory.exemplarFrames(seed: 1, count: 10)))
        try await store.save(SignExemplar(lexID: "water", frames: FeatureFactory.exemplarFrames(seed: 2, count: 10)))
        try await store.save(SignExemplar(lexID: "help", frames: FeatureFactory.exemplarFrames(seed: 3, count: 10)))

        let counts = try await store.counts()
        #expect(counts["water"] == 2)
        #expect(counts["help"] == 1)
    }

    @Test func removeAllClearsOneSign() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await store.save(SignExemplar(lexID: "water", frames: FeatureFactory.exemplarFrames(seed: 1, count: 10)))
        try await store.save(SignExemplar(lexID: "help", frames: FeatureFactory.exemplarFrames(seed: 2, count: 10)))
        try await store.removeAll(for: "water")

        let counts = try await store.counts()
        #expect(counts["water"] == nil)
        #expect(counts["help"] == 1)
    }

    @Test func mismatchedLayoutVersionIsSkipped() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A future-layout exemplar must not be loaded (would be misinterpreted).
        let stale = SignExemplar(id: UUID(),
                                 lexID: "water",
                                 layoutVersion: FeatureExtractor.Layout.version + 99,
                                 frames: FeatureFactory.exemplarFrames(seed: 1, count: 10),
                                 recordedAt: .now)
        try await store.save(stale)

        #expect(try await store.loadAll().isEmpty)
    }
}
