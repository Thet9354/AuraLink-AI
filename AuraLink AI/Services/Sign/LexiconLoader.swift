//
//  LexiconLoader.swift
//  AuraLink AI
//
//  Loads the bundled v1 catalog. Fails soft to an empty lexicon (the pipeline then reports
//  "no signs enrolled" rather than crashing) — but that is logged as a real setup error.
//

import Foundation
import os

nonisolated enum LexiconLoader {
    private static let log = Logger(subsystem: Signposts.subsystem, category: "lexicon")

    static func loadBundled() -> SignLexicon {
        guard let url = Bundle.main.url(forResource: "lexicon_v1", withExtension: "json") else {
            log.error("lexicon_v1.json missing from bundle")
            return SignLexicon(entries: [])
        }
        do {
            return try SignLexicon.load(from: url)
        } catch {
            log.error("lexicon decode failed: \(error.localizedDescription, privacy: .public)")
            return SignLexicon(entries: [])
        }
    }
}
