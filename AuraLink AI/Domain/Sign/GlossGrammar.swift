//
//  GlossGrammar.swift
//  AuraLink AI
//
//  Renders a sequence of recognized glosses into readable English caption spans. v1 is a rule
//  layer — deliberately modest and testable:
//    • pronoun surface mapping (ME → "I")
//    • sentence casing and terminal punctuation ("?" when the sentence contains a question sign)
//    • confidence-aware span weights; unrecognized segments render as an explicit "…" gap
//  Full ASL topic-comment → SVO reordering is future work behind this same seam; being honest
//  about gloss order beats pretending to fluent syntax.
//

nonisolated enum GlossGrammar {

    /// One recognized (or unrecognized) segment in the current sentence window.
    struct Item: Sendable {
        /// The matched entry, or nil for an out-of-vocabulary segment.
        var entry: LexEntry?
        var confidence: Float
    }

    /// Span weight thresholds. Below the matcher's unknown gate a segment never gets here at all.
    static let confidentThreshold: Float = 0.7

    static func render(_ items: [Item]) -> (spans: [StyledSpan], band: ConfidenceBand) {
        guard !items.isEmpty else { return ([], .low) }

        var spans: [StyledSpan] = []
        var minConfidence: Float = 1
        var isQuestion = false

        for (index, item) in items.enumerated() {
            guard let entry = item.entry else {
                spans.append(StyledSpan(text: "…", weight: .unknown))
                minConfidence = 0
                continue
            }
            if entry.category == .question { isQuestion = true }

            var text = surface(for: entry)
            if index == 0 || spans.isEmpty {
                text = capitalizeFirst(text)
            }
            let weight: SpanWeight = item.confidence >= confidentThreshold ? .confident : .tentative
            spans.append(StyledSpan(text: text, weight: weight))
            minConfidence = min(minConfidence, item.confidence)
        }

        // Terminal punctuation on the last non-gap span.
        if let lastIndex = spans.lastIndex(where: { $0.weight != .unknown }) {
            spans[lastIndex].text += isQuestion ? "?" : "."
        }

        let band: ConfidenceBand = minConfidence >= 0.7 ? .high : (minConfidence >= 0.5 ? .medium : .low)
        return (spans, band)
    }

    /// English surface for an entry, with pronoun mapping. ASL glosses index the signer as ME;
    /// English captions speak as "I".
    static func surface(for entry: LexEntry) -> String {
        switch entry.id {
        case "me": return "I"
        default: return entry.english
        }
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
