//
//  GlossGrammarTests.swift
//  AuraLink AITests
//
//  Phase 3 gate: gloss → readable English rendering — pronoun mapping, casing, question
//  punctuation, honest unknown gaps, and confidence-band derivation.
//

import Testing
@testable import AuraLink_AI

struct GlossGrammarTests {

    private func entry(_ id: String, _ english: String, _ category: LexEntry.Category) -> LexEntry {
        LexEntry(id: id, gloss: id.uppercased(), english: english, category: category)
    }

    private func item(_ entry: LexEntry?, _ confidence: Float) -> GlossGrammar.Item {
        GlossGrammar.Item(entry: entry, confidence: confidence)
    }

    @Test func mapsMeToIAndCapitalizesAndPunctuates() {
        let items = [
            item(entry("me", "me", .person), 0.9),
            item(entry("need", "need", .need), 0.9),
            item(entry("water", "water", .need), 0.9)
        ]
        let (spans, band) = GlossGrammar.render(items)
        let text = spans.map(\.text).joined(separator: " ")
        #expect(text == "I need water.")
        #expect(band == .high)
    }

    @Test func questionSignYieldsQuestionMark() {
        let items = [
            item(entry("where", "where", .question), 0.9),
            item(entry("bathroom", "bathroom", .place), 0.9)
        ]
        let (spans, _) = GlossGrammar.render(items)
        #expect(spans.map(\.text).joined(separator: " ") == "Where bathroom?")
    }

    @Test func unknownRendersAsGapAndLowersBand() {
        let items = [
            item(entry("me", "me", .person), 0.9),
            item(nil, 0),
            item(entry("water", "water", .need), 0.9)
        ]
        let (spans, band) = GlossGrammar.render(items)
        #expect(spans.contains { $0.weight == .unknown && $0.text == "…" })
        #expect(band == .low)   // an unknown drops overall confidence
    }

    @Test func lowConfidenceMatchIsTentative() {
        let items = [item(entry("water", "water", .need), 0.55)]
        let (spans, band) = GlossGrammar.render(items)
        #expect(spans.first?.weight == .tentative)
        #expect(band == .medium)
    }

    @Test func emptyInputIsEmpty() {
        let (spans, band) = GlossGrammar.render([])
        #expect(spans.isEmpty)
        #expect(band == .low)
    }

    @Test func punctuationLandsOnLastRealSpanNotGap() {
        let items = [
            item(entry("help", "help", .need), 0.9),
            item(nil, 0)
        ]
        let (spans, _) = GlossGrammar.render(items)
        // The last non-gap span carries the period; the trailing gap stays "…".
        #expect(spans.first?.text == "Help.")
        #expect(spans.last?.text == "…")
    }
}
