//
//  CaptionDTO.swift
//  AuraLink AI
//
//  The frozen, UI-facing translation value. This is the ONLY pipeline product the `@MainActor`
//  view model ever sees — never a reference into the pipeline — which severs any accidental
//  shared-mutable-state path from the background actors to the UI.
//
//  Pure Domain value types, explicitly `nonisolated` so they cross actor boundaries.
//

import Foundation

/// Which modality produced a caption.
nonisolated enum CaptionSource: Sendable {
    case sign
    case speech
}

/// Overall confidence band for a caption, used to style the whole line and to decide spoken
/// intonation. Honest, calibrated confidence is a first-class accessibility feature: a
/// low-confidence translation must never be presented as fact.
nonisolated enum ConfidenceBand: Sendable {
    case high
    case medium
    case low
}

/// Per-span rendering weight. Sub-threshold tokens render distinctly (`.tentative`) or as an
/// explicit gap (`.unknown`) rather than being fabricated into a confident word.
nonisolated enum SpanWeight: Sendable {
    case confident
    case tentative
    case unknown
}

/// A styled run of caption text.
nonisolated struct StyledSpan: Sendable, Identifiable {
    let id: UUID
    var text: String
    var weight: SpanWeight

    init(id: UUID = UUID(), text: String, weight: SpanWeight) {
        self.id = id
        self.text = text
        self.weight = weight
    }
}

/// A complete, frozen caption ready for rendering.
nonisolated struct CaptionDTO: Sendable, Identifiable {
    let id: UUID
    var spans: [StyledSpan]
    var band: ConfidenceBand
    /// Measured glass-to-caption latency for this result, surfaced in the HUD.
    var latencyMs: Int
    var source: CaptionSource
    var timestamp: Date
    /// The text just recognized this update, to be spoken aloud once. `nil` when nothing new/spoken
    /// (e.g. an unknown sign or a system message).
    var utterance: String?
    /// The runner-up sign, surfaced as "did you mean…?" when the match confidence is low.
    var alternative: String?

    init(id: UUID = UUID(),
         spans: [StyledSpan],
         band: ConfidenceBand,
         latencyMs: Int,
         source: CaptionSource,
         timestamp: Date,
         utterance: String? = nil,
         alternative: String? = nil) {
        self.id = id
        self.spans = spans
        self.band = band
        self.latencyMs = latencyMs
        self.source = source
        self.timestamp = timestamp
        self.utterance = utterance
        self.alternative = alternative
    }

    var plainText: String {
        spans.map(\.text).joined(separator: " ")
    }
}
