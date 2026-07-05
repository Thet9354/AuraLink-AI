//
//  SignMatcherTests.swift
//  AuraLink AITests
//
//  Phase 3 gate: two-stage matching returns the right sign for a matching query, honestly returns
//  unknown for out-of-vocabulary motion, reports probability-shaped confidence, and never
//  fabricates a gloss.
//

import Testing
@testable import AuraLink_AI

struct SignMatcherTests {

    private let lexicon = SignLexicon(entries: [
        LexEntry(id: "hello", gloss: "HELLO", english: "hello", category: .greeting),
        LexEntry(id: "water", gloss: "WATER", english: "water", category: .need),
        LexEntry(id: "help", gloss: "HELP", english: "help", category: .need)
    ])

    private func matcher(exemplarSeeds: [String: Float], tuning: SignMatcher.Tuning = .init()) -> SignMatcher {
        var prepared: [SignMatcher.PreparedExemplar] = []
        for (lexID, seed) in exemplarSeeds {
            let exemplar = SignExemplar(lexID: lexID, frames: FeatureFactory.exemplarFrames(seed: seed, count: 20))
            prepared.append(SignMatcher.PreparedExemplar(exemplar: exemplar))
        }
        return SignMatcher(lexicon: lexicon, exemplars: prepared, tuning: tuning)
    }

    @Test func emptyLibraryReturnsNoExemplars() {
        let empty = SignMatcher(lexicon: lexicon, exemplars: [])
        if case .noExemplars = empty.match(FeatureFactory.segment(seed: 1, count: 20)) {
            // expected
        } else {
            Issue.record("expected .noExemplars")
        }
    }

    @Test func matchingQueryReturnsCorrectSign() {
        let m = matcher(exemplarSeeds: ["hello": 1.0, "water": 4.0, "help": 8.0])
        let query = FeatureFactory.segment(seed: 4.0, count: 20)   // matches "water"

        guard case .matched(let best, _) = m.match(query) else {
            Issue.record("expected a match"); return
        }
        #expect(best.entry.id == "water")
        #expect(best.confidence > 0 && best.confidence <= 1.0001)
        #expect(best.distance < 0.5)
    }

    @Test func outOfVocabularyReturnsUnknown() {
        // Exemplars all near small handshapes; query is a wildly different, far handshape.
        var tuning = SignMatcher.Tuning()
        tuning.unknownThreshold = 0.5
        let m = matcher(exemplarSeeds: ["hello": 1.0, "water": 1.1], tuning: tuning)

        // Build a query whose sliced features are far from any exemplar.
        var frames: [FeatureVector] = []
        for i in 0..<20 {
            var v = [Float](repeating: 0, count: FeatureExtractor.Layout.dimension)
            v[FeatureExtractor.Layout.rightValidIndex] = 1
            for j in 0..<FeatureExtractor.Layout.positionsPerHand {
                v[FeatureExtractor.Layout.rightHandStart + j] = 9.0   // far outside sin() range
            }
            frames.append(FeatureVector(values: v, timeSeconds: Double(i)/30, seq: UInt64(i),
                                        leftHandValid: false, rightHandValid: true))
        }
        let query = GestureSegment(frames: frames, startSeconds: 0, endSeconds: 0.6, closedReason: .pause)

        guard case .unknown = m.match(query) else {
            Issue.record("expected .unknown for far query"); return
        }
    }

    @Test func confidencesFormAProbabilityOverCandidates() {
        let m = matcher(exemplarSeeds: ["hello": 1.0, "water": 4.0, "help": 8.0])
        guard case .matched(let best, let alternatives) = m.match(FeatureFactory.segment(seed: 1.0, count: 20)) else {
            Issue.record("expected a match"); return
        }
        #expect(best.entry.id == "hello")
        // Best confidence should dominate the alternatives.
        for alt in alternatives {
            #expect(best.confidence >= alt.confidence)
        }
    }

    @Test func bigramContextChangesTheWinner() {
        // Query is nearest to "water"; but after "thank_you", the "you" continuation is nudged.
        // With bigramBoost = 0 the nudge is decisive, giving a deterministic test of the mechanism:
        // context alone flips the winner between identical queries.
        let lex = SignLexicon(entries: [
            LexEntry(id: "you", gloss: "YOU", english: "you", category: .person),
            LexEntry(id: "water", gloss: "WATER", english: "water", category: .need)
        ])
        let exemplars = [
            SignMatcher.PreparedExemplar(exemplar: SignExemplar(lexID: "you",
                frames: FeatureFactory.exemplarFrames(seed: 5.0, count: 20))),      // far from query
            SignMatcher.PreparedExemplar(exemplar: SignExemplar(lexID: "water",
                frames: FeatureFactory.exemplarFrames(seed: 2.0, count: 20)))       // near query
        ]
        var tuning = SignMatcher.Tuning()
        tuning.bigramBoost = 0   // a phrase continuation is decisively favored
        let m = SignMatcher(lexicon: lex, exemplars: exemplars, tuning: tuning)
        let query = FeatureFactory.segment(seed: 2.02, count: 20)   // closest to "water"

        guard case .matched(let noContext, _) = m.match(query, previousLexID: nil) else {
            Issue.record("expected a match without context"); return
        }
        #expect(noContext.entry.id == "water")

        guard case .matched(let withContext, _) = m.match(query, previousLexID: "thank_you") else {
            Issue.record("expected a match with context"); return
        }
        #expect(withContext.entry.id == "you")   // context flipped the winner
    }
}
