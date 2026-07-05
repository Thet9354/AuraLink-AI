//
//  CustomPhrase.swift
//  AuraLink AI
//
//  A user-created gesture→text binding. This is what turns AuraLink from a fixed-vocabulary
//  translator into a personal, offline communicator (AAC): the user assigns ANY text — a word or a
//  whole sentence like "I need to use the bathroom" — to a gesture they invent, and it is spoken
//  aloud when recognized. Custom phrases flow through the exact same recognition path as the
//  catalog by presenting as `LexEntry`s.
//

import Foundation

nonisolated struct CustomPhrase: Sendable, Codable, Identifiable {
    /// Stable lexicon id (also the key exemplars are recorded against).
    let id: String
    /// Short label shown in the enrollment list.
    var title: String
    /// The text displayed and spoken when the gesture is recognized.
    var text: String
    var createdAt: Date

    init(id: String = "custom_\(UUID().uuidString)",
         title: String,
         text: String,
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }

    /// Presents as a lexicon entry so it recognizes/renders through the standard pipeline.
    var asLexEntry: LexEntry {
        LexEntry(id: id,
                 gloss: title.uppercased(),
                 english: text,
                 category: .custom)
    }
}
