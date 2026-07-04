//
//  MockCaptionPipeline.swift
//  AuraLink AI
//
//  Phase 0 stand-in for the real capture → vision → fusion → inference graph. It exists to
//  exercise the production side of the `LatestSlot` back-pressure contract end-to-end before any
//  hardware is wired: it emits mock ASL "Everyday Needs" captions at a variable, tier-bounded
//  rate. If the UI consumer lags, stale captions are overwritten (dropped), not queued.
//
//  Replaced in Phase 3 by the real `SignRecognizing` pipeline behind the same `CaptionProducing`
//  seam.
//

import Foundation
import os

actor MockCaptionPipeline: CaptionProducing {

    /// `nonisolated` so the view-model consumer can grab the slot reference without an actor hop.
    /// Safe because `LatestSlot` is itself an actor (its own isolation domain).
    nonisolated let output = LatestSlot<CaptionDTO>()

    private let tier: CapabilityTier
    private var producer: Task<Void, Never>?

    init(tier: CapabilityTier) {
        self.tier = tier
    }

    /// A slice of the ~200-sign v1 "Everyday Needs" ASL vocabulary, as gloss word sequences.
    private static let samplePhrases: [[String]] = [
        ["hello"],
        ["how", "are", "you"],
        ["i", "need", "water"],
        ["where", "is", "the", "restroom"],
        ["thank", "you"],
        ["help", "please"],
        ["yes"],
        ["no"],
        ["my", "name", "is", "thet"],
        ["nice", "to", "meet", "you"]
    ]

    func start() {
        guard producer == nil else { return }
        let tier = self.tier
        let output = self.output
        producer = Task {
            var index = 0
            while !Task.isCancelled {
                let words = Self.samplePhrases[index % Self.samplePhrases.count]
                index += 1

                // Simulate variable inference latency, bounded by the tier's inference budget.
                let frameMs = 1000 / max(tier.fpsCaps.signInferenceHz, 1)
                let latencyMs = Int.random(in: frameMs...(frameMs * 3))
                let interval = Signposts.pipeline.beginInterval("mockInference")
                try? await Task.sleep(for: .milliseconds(latencyMs))
                Signposts.pipeline.endInterval("mockInference", interval)

                // Occasionally emit a tentative/unknown span to exercise confidence-aware rendering.
                let spans = Self.styledSpans(for: words, index: index)
                let band: ConfidenceBand = (index % 7 == 0) ? .low : .high
                let dto = CaptionDTO(spans: spans,
                                     band: band,
                                     latencyMs: latencyMs,
                                     source: .sign,
                                     timestamp: .now)

                // Overwrites if the UI has not consumed the previous caption — intentional drop.
                await output.put(dto)
            }
        }
    }

    func stop() {
        producer?.cancel()
        producer = nil
    }

    private static func styledSpans(for words: [String], index: Int) -> [StyledSpan] {
        words.enumerated().map { offset, word in
            let weight: SpanWeight
            if index % 7 == 0 && offset == words.count - 1 {
                weight = .unknown          // simulate an out-of-vocabulary sign
            } else if index % 5 == 0 && offset == 0 {
                weight = .tentative        // simulate a low-confidence match
            } else {
                weight = .confident
            }
            return StyledSpan(text: weight == .unknown ? "…" : word, weight: weight)
        }
    }
}
