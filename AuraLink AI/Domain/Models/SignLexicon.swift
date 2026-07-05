//
//  SignLexicon.swift
//  AuraLink AI
//
//  The v1 "Everyday Needs" ASL vocabulary catalog (~200 signs). The catalog carries METADATA only
//  (gloss ids, English surface forms, categories) — the pose exemplars that make a sign
//  recognizable are recorded on device and live in the exemplar store. Out-of-catalog signs are
//  rendered honestly as unknown, never guessed.
//

import Foundation

/// One catalog entry. `id` is the stable key exemplars are recorded against.
nonisolated struct LexEntry: Sendable, Codable, Identifiable, Hashable {
    /// Stable snake_case identifier, e.g. "thank_you".
    let id: String
    /// Conventional ASL gloss notation (uppercase), e.g. "THANK-YOU".
    let gloss: String
    /// English surface form used in rendered captions, e.g. "thank you".
    let english: String
    /// Grouping for the enrollment UI and grammar hints (e.g. "question" drives "?").
    let category: Category

    nonisolated enum Category: String, Sendable, Codable, CaseIterable {
        case greeting, courtesy, response, need, food, health, emergency
        case question, place, direction, time, person, feeling, action, number
    }
}

/// The loaded catalog with id-keyed lookup.
nonisolated struct SignLexicon: Sendable {
    let entries: [LexEntry]
    private let byID: [String: LexEntry]

    init(entries: [LexEntry]) {
        self.entries = entries
        self.byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    subscript(id: String) -> LexEntry? { byID[id] }
    var count: Int { entries.count }

    func entries(in category: LexEntry.Category) -> [LexEntry] {
        entries.filter { $0.category == category }
    }

    /// Decodes the bundled catalog JSON (an array of `LexEntry`).
    static func load(from url: URL) throws -> SignLexicon {
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([LexEntry].self, from: data)
        return SignLexicon(entries: entries)
    }
}
