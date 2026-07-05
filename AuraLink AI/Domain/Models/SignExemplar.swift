//
//  SignExemplar.swift
//  AuraLink AI
//
//  One recorded reference performance of a sign — the unit of DTW few-shot matching and of
//  Phase 5 personalization (enrollment simply records the user's own exemplars). Serialized to
//  disk; `layoutVersion` guards against feature-layout drift (a mismatched exemplar is skipped,
//  never misinterpreted).
//

import Foundation

nonisolated struct SignExemplar: Sendable, Codable, Identifiable {
    let id: UUID
    /// The `LexEntry.id` this exemplar demonstrates.
    let lexID: String
    /// `FeatureExtractor.Layout.version` at recording time.
    let layoutVersion: Int
    /// Per-frame feature values (each `FeatureExtractor.Layout.dimension` long), oldest → newest.
    let frames: [[Float]]
    /// Recording timestamp (for pruning/replacing during enrollment).
    let recordedAt: Date

    init(id: UUID = UUID(),
         lexID: String,
         layoutVersion: Int = FeatureExtractor.Layout.version,
         frames: [[Float]],
         recordedAt: Date = .now) {
        self.id = id
        self.lexID = lexID
        self.layoutVersion = layoutVersion
        self.frames = frames
        self.recordedAt = recordedAt
    }

    /// Convenience: build from a captured segment.
    init(lexID: String, segment: GestureSegment) {
        self.init(lexID: lexID, frames: segment.frames.map(\.values))
    }
}
