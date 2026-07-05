//
//  SignMatcher.swift
//  AuraLink AI
//
//  Two-stage few-shot recognition over the exemplar library:
//
//    Stage 1 — PRUNE (cheap): duration-ratio gate, then mean-frame distance ranks all candidates
//              and keeps the top K. ~200 signs × few exemplars stays microseconds.
//    Stage 2 — DTW (exact): full banded DTW against the survivors; best exemplar per sign wins.
//
//  Confidence is calibrated two ways, both required:
//    • ABSOLUTE gate: if even the best distance is worse than `unknownThreshold`, the segment is
//      out-of-vocabulary → `.unknown`. Never fabricate a gloss.
//    • RELATIVE softmax over per-sign distances → a probability-shaped confidence whose
//      calibration is validated with reliability diagrams once real exemplars exist.
//
//  A small authored bigram table nudges candidates that continue a common phrase (THANK+YOU) —
//  the v1 stand-in for the LM rescoring stage, behind the same call site.
//

import Foundation

nonisolated struct SignMatcher: Sendable {

    struct Tuning: Sendable {
        /// Segment/exemplar duration ratio outside [1/durationRatioLimit, durationRatioLimit]
        /// is pruned — DTW's band would reject it anyway, so don't pay for the DP.
        var durationRatioLimit: Float = 2.5
        /// Candidates surviving to full DTW.
        var pruneTopK: Int = 25
        /// Absolute per-step DTW distance above which the segment is out-of-vocabulary.
        /// Tunable against real exemplars; deliberately strict — honesty over coverage.
        var unknownThreshold: Float = 1.1
        /// Softmax temperature for relative confidence.
        var temperature: Float = 0.25
        /// Distance multiplier for candidates continuing a known bigram (< 1 = boost).
        var bigramBoost: Float = 0.85

        init() {}
    }

    /// Common two-sign sequences in the Everyday Needs domain, as (previous, candidate) lex ids.
    static let commonBigrams: Set<String> = [
        "thank_you|you", "how|you", "nice|meet", "what|name", "where|bathroom",
        "where|hospital", "need|help", "need|water", "want|water", "want|eat",
        "how_much|money", "i|need", "i|want", "you|ok"
    ]

    enum MatchResult: Sendable {
        /// Best candidate plus ranked alternatives (for the predictive UI later).
        case matched(best: Candidate, alternatives: [Candidate])
        /// Motion was seen but nothing in the vocabulary is close enough. Rendered as "…".
        case unknown(bestDistance: Float)
        /// The library has no usable exemplars yet (pre-enrollment).
        case noExemplars
    }

    struct Candidate: Sendable {
        let entry: LexEntry
        let confidence: Float
        let distance: Float
    }

    /// An exemplar prepared for matching (sliced once at load, not per segment).
    struct PreparedExemplar: Sendable {
        let lexID: String
        let frames: [DTWFrame]
        let meanFrame: DTWFrame
        let frameCount: Int

        init(exemplar: SignExemplar) {
            self.lexID = exemplar.lexID
            let frames = exemplar.frames.map(SignFeatureSlice.slice(exemplarFrame:))
            self.frames = frames
            self.meanFrame = DTW.meanFrame(frames)
            self.frameCount = frames.count
        }
    }

    let lexicon: SignLexicon
    let exemplars: [PreparedExemplar]
    let tuning: Tuning

    init(lexicon: SignLexicon, exemplars: [PreparedExemplar], tuning: Tuning = Tuning()) {
        self.lexicon = lexicon
        self.exemplars = exemplars
        self.tuning = tuning
    }

    func match(_ segment: GestureSegment, previousLexID: String? = nil) -> MatchResult {
        guard !exemplars.isEmpty else { return .noExemplars }

        let query = segment.frames.map(SignFeatureSlice.slice)
        guard !query.isEmpty else { return .unknown(bestDistance: .infinity) }
        let queryMean = DTW.meanFrame(query)
        let queryCount = Float(query.count)

        // Stage 1 — prune by duration ratio, rank by mean-frame distance.
        let pruned = exemplars
            .filter { exemplar in
                let ratio = queryCount / Float(exemplar.frameCount)
                return ratio <= tuning.durationRatioLimit && ratio >= 1 / tuning.durationRatioLimit
            }
            .map { exemplar in
                (exemplar, DTW.frameDistance(queryMean, exemplar.meanFrame))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(tuning.pruneTopK)

        guard !pruned.isEmpty else { return .unknown(bestDistance: .infinity) }

        // Stage 2 — full DTW; keep the best exemplar per sign, with the bigram nudge.
        var bestPerSign: [String: Float] = [:]
        for (exemplar, _) in pruned {
            var distance = DTW.distance(query, exemplar.frames)
            if let previous = previousLexID,
               Self.commonBigrams.contains("\(previous)|\(exemplar.lexID)") {
                distance *= tuning.bigramBoost
            }
            if distance < bestPerSign[exemplar.lexID] ?? .infinity {
                bestPerSign[exemplar.lexID] = distance
            }
        }

        let ranked = bestPerSign.sorted { $0.value < $1.value }
        guard let best = ranked.first, best.value <= tuning.unknownThreshold else {
            return .unknown(bestDistance: ranked.first?.value ?? .infinity)
        }

        // Relative confidence: softmax(−distance/τ) over the surviving signs.
        let weights = ranked.map { expf(-$0.value / tuning.temperature) }
        let total = weights.reduce(0, +)
        let candidates: [Candidate] = zip(ranked, weights).compactMap { pair, weight in
            guard let entry = lexicon[pair.key] else { return nil }
            return Candidate(entry: entry, confidence: weight / total, distance: pair.value)
        }

        guard let top = candidates.first else { return .unknown(bestDistance: best.value) }
        return .matched(best: top, alternatives: Array(candidates.dropFirst().prefix(3)))
    }
}
